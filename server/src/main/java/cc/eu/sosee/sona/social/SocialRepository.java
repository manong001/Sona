package cc.eu.sosee.sona.social;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Clock;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

import static org.springframework.http.HttpStatus.BAD_REQUEST;
import static org.springframework.http.HttpStatus.CONFLICT;
import static org.springframework.http.HttpStatus.FORBIDDEN;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@Repository
class SocialRepository {

    private static final long ONLINE_WINDOW_MILLIS = 60_000;

    private final JdbcClient jdbcClient;
    private final Clock clock;
    private final ObjectMapper objectMapper;

    SocialRepository(JdbcClient jdbcClient, Clock clock, ObjectMapper objectMapper) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
        this.objectMapper = objectMapper;
    }

    SocialUserResponse profile(AuthenticatedUser actor) {
        return user(actor.id(), actor, null, null, null);
    }

    SocialUserResponse updateProfile(
        AuthenticatedUser actor, String displayName, String signature
    ) {
        jdbcClient.sql("""
                UPDATE users
                SET display_name = :displayName, signature = :signature
                WHERE id = :id
                """)
            .param("displayName", blankToNull(displayName))
            .param("signature", signature)
            .param("id", actor.id())
            .update();
        return profile(actor);
    }

    void touch(String userId) {
        jdbcClient.sql("UPDATE users SET last_seen_at = :now WHERE id = :id")
            .param("now", clock.millis())
            .param("id", userId)
            .update();
    }

    List<SocialUserResponse> searchUsers(AuthenticatedUser actor, String query) {
        return jdbcClient.sql("""
                SELECT id FROM users
                WHERE id <> :actorId AND enabled = 1
                  AND (username LIKE :query COLLATE NOCASE
                    OR COALESCE(display_name, '') LIKE :query COLLATE NOCASE)
                ORDER BY username COLLATE NOCASE
                LIMIT 30
                """)
            .param("actorId", actor.id())
            .param("query", "%" + query + "%")
            .query((row, number) -> user(
                row.getString("id"), actor, isFriend(actor.id(), row.getString("id")), null, null
            ))
            .list();
    }

    List<SocialUserResponse> friends(AuthenticatedUser actor) {
        return jdbcClient.sql("""
                SELECT CASE WHEN user_low_id = :actorId THEN user_high_id ELSE user_low_id END AS id
                FROM friendships
                WHERE user_low_id = :actorId OR user_high_id = :actorId
                ORDER BY created_at DESC
                """)
            .param("actorId", actor.id())
            .query((row, number) -> conversationUser(row.getString("id"), actor, true))
            .list();
    }

    List<SocialUserResponse> conversations(AuthenticatedUser actor) {
        return jdbcClient.sql("""
                SELECT peer_id, MAX(created_at) AS latest FROM (
                    SELECT recipient_id AS peer_id, created_at FROM messages WHERE sender_id = :actorId
                    UNION ALL
                    SELECT sender_id AS peer_id, created_at FROM messages WHERE recipient_id = :actorId
                ) GROUP BY peer_id ORDER BY latest DESC
                """)
            .param("actorId", actor.id())
            .query((row, number) -> conversationUser(
                row.getString("peer_id"), actor, isFriend(actor.id(), row.getString("peer_id"))
            ))
            .list();
    }

    @Transactional
    SocialUserResponse addFriend(AuthenticatedUser actor, String username) {
        var peerId = jdbcClient.sql("""
                SELECT id FROM users
                WHERE username = :username COLLATE NOCASE AND enabled = 1
                """)
            .param("username", username)
            .query(String.class)
            .optional()
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "User not found"));
        if (peerId.equals(actor.id())) {
            throw new ResponseStatusException(BAD_REQUEST, "You cannot add yourself");
        }
        var pair = pair(actor.id(), peerId);
        jdbcClient.sql("""
                INSERT OR IGNORE INTO friendships(user_low_id, user_high_id, created_by, created_at)
                VALUES (:low, :high, :actorId, :createdAt)
                """)
            .param("low", pair[0])
            .param("high", pair[1])
            .param("actorId", actor.id())
            .param("createdAt", clock.millis())
            .update();
        return user(peerId, actor, true, null, null);
    }

    void deleteFriend(String actorId, String peerId) {
        var pair = pair(actorId, peerId);
        jdbcClient.sql("DELETE FROM friendships WHERE user_low_id = :low AND user_high_id = :high")
            .param("low", pair[0])
            .param("high", pair[1])
            .update();
    }

    @Transactional
    List<SocialMessageResponse> messages(AuthenticatedUser actor, String peerId) {
        requireUser(peerId);
        if (!isFriend(actor.id(), peerId) && !hasMessageHistory(actor.id(), peerId)) {
            throw new ResponseStatusException(FORBIDDEN, "Add this user as a friend first");
        }
        jdbcClient.sql("""
                UPDATE messages SET read_at = :now
                WHERE sender_id = :peerId AND recipient_id = :actorId AND read_at IS NULL
                """)
            .param("now", clock.millis())
            .param("peerId", peerId)
            .param("actorId", actor.id())
            .update();
        return jdbcClient.sql("""
                SELECT * FROM messages
                WHERE (sender_id = :actorId AND recipient_id = :peerId)
                   OR (sender_id = :peerId AND recipient_id = :actorId)
                ORDER BY created_at, id LIMIT 500
                """)
            .param("actorId", actor.id())
            .param("peerId", peerId)
            .query((row, number) -> message(row, actor.id()))
            .list();
    }

    SocialMessageResponse sendMessage(
        AuthenticatedUser actor,
        String recipientId,
        String clientMessageId,
        String kind,
        String text,
        Map<String, Object> payload
    ) {
        if (!isFriend(actor.id(), recipientId)) {
            throw new ResponseStatusException(FORBIDDEN, "The recipient is not your friend");
        }
        var normalizedKind = kind.toUpperCase();
        var normalizedText = text == null ? "" : text.strip();
        switch (normalizedKind) {
            case "TEXT" -> {
                if (normalizedText.isEmpty() || normalizedText.length() > 2_000) {
                    throw new ResponseStatusException(BAD_REQUEST, "Text messages must be 1-2000 characters");
                }
            }
            case "STICKER" -> {
                if (normalizedText.isEmpty() || normalizedText.length() > 64) {
                    throw new ResponseStatusException(BAD_REQUEST, "Invalid sticker");
                }
            }
            case "TRACK" -> {
                if (payload == null || blank(payload.get("id")) || blank(payload.get("title"))) {
                    throw new ResponseStatusException(BAD_REQUEST, "Track information is incomplete");
                }
            }
            default -> throw new ResponseStatusException(BAD_REQUEST, "Unknown message kind");
        }
        if (clientMessageId != null && !clientMessageId.isBlank()) {
            var existing = jdbcClient.sql("""
                    SELECT * FROM messages WHERE sender_id = :senderId AND client_message_id = :clientId
                    """)
                .param("senderId", actor.id())
                .param("clientId", clientMessageId)
                .query((row, number) -> message(row, actor.id()))
                .optional();
            if (existing.isPresent()) {
                return existing.get();
            }
        }
        var id = UUID.randomUUID().toString();
        var createdAt = clock.millis();
        jdbcClient.sql("""
                INSERT INTO messages(
                    id, sender_id, recipient_id, client_message_id, kind, text,
                    payload_json, created_at
                ) VALUES (
                    :id, :senderId, :recipientId, :clientId, :kind, :text,
                    :payload, :createdAt
                )
                """)
            .param("id", id)
            .param("senderId", actor.id())
            .param("recipientId", recipientId)
            .param("clientId", blankToNull(clientMessageId))
            .param("kind", normalizedKind)
            .param("text", normalizedText)
            .param("payload", payload == null ? null : json(payload))
            .param("createdAt", createdAt)
            .update();
        return findMessage(id, actor.id());
    }

    SocialMessageResponse recall(AuthenticatedUser actor, String messageId) {
        var current = findMessage(messageId, actor.id());
        if (!current.senderId().equals(actor.id())) {
            throw new ResponseStatusException(FORBIDDEN, "Only your own messages can be recalled");
        }
        if (current.recalledAt() != null || clock.millis() - current.createdAt() > 120_000) {
            throw new ResponseStatusException(CONFLICT, "The recall window has expired");
        }
        jdbcClient.sql("UPDATE messages SET recalled_at = :now WHERE id = :id")
            .param("now", clock.millis())
            .param("id", messageId)
            .update();
        return findMessage(messageId, actor.id());
    }

    SocialMediaFile addMedia(
        String userId, String kind, String mimeType, String originalName, String storagePath,
        long sizeBytes, String groupId, String component
    ) {
        var id = UUID.randomUUID().toString();
        jdbcClient.sql("""
                INSERT INTO social_media(
                    id, user_id, kind, mime_type, original_name, group_id, component,
                    storage_path, size_bytes, created_at
                ) VALUES (
                    :id, :userId, :kind, :mimeType, :originalName, :groupId, :component,
                    :storagePath, :sizeBytes, :createdAt
                )
                """)
            .param("id", id)
            .param("userId", userId)
            .param("kind", kind)
            .param("mimeType", mimeType)
            .param("originalName", originalName)
            .param("groupId", blankToNull(groupId))
            .param("component", blankToNull(component))
            .param("storagePath", storagePath)
            .param("sizeBytes", sizeBytes)
            .param("createdAt", clock.millis())
            .update();
        return media(id);
    }

    SocialMediaFile media(String id) {
        return jdbcClient.sql("SELECT * FROM social_media WHERE id = :id")
            .param("id", id)
            .query(this::mapMedia)
            .optional()
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Media not found"));
    }

    boolean canAccessMedia(String actorId, SocialMediaFile media) {
        if (media.userId().equals(actorId) || isFriend(actorId, media.userId())) {
            return true;
        }
        return false;
    }

    @Transactional
    SocialMomentResponse createMoment(AuthenticatedUser actor, String text, List<String> mediaIds) {
        var body = text == null ? "" : text.strip();
        var ids = mediaIds == null ? List.<String>of() : mediaIds.stream().distinct().toList();
        if (body.length() > 2_000 || ids.size() > 21 || body.isBlank() && ids.isEmpty()) {
            throw new ResponseStatusException(BAD_REQUEST, "Invalid moment content");
        }
        var media = ids.stream().map(this::media).toList();
        if (media.stream().anyMatch(value -> !value.userId().equals(actor.id()))) {
            throw new ResponseStatusException(BAD_REQUEST, "Media must belong to the current user");
        }
        var imageKeys = new HashSet<String>();
        var liveComponents = new java.util.HashMap<String, Set<String>>();
        for (var value : media) {
            if (value.kind().equals("VIDEO")) {
                continue;
            }
            if (value.kind().equals("LIVE_PHOTO") && value.groupId() != null) {
                imageKeys.add("LIVE_PHOTO:" + value.groupId());
                liveComponents.computeIfAbsent(value.groupId(), ignored -> new HashSet<>())
                    .add(value.component());
            } else {
                imageKeys.add(value.id());
            }
        }
        if (liveComponents.values().stream().anyMatch(
            components -> !components.containsAll(Set.of("photo", "video"))
        )) {
            throw new ResponseStatusException(BAD_REQUEST, "Live photo components are incomplete");
        }
        long images = imageKeys.size();
        long videos = media.stream().filter(value -> value.kind().equals("VIDEO")).count();
        if (images > 9 || videos > 3) {
            throw new ResponseStatusException(BAD_REQUEST, "A moment allows 9 images and 3 videos");
        }
        var id = UUID.randomUUID().toString();
        jdbcClient.sql("INSERT INTO moments(id, user_id, text, created_at) VALUES (:id, :userId, :text, :now)")
            .param("id", id)
            .param("userId", actor.id())
            .param("text", body)
            .param("now", clock.millis())
            .update();
        for (int index = 0; index < ids.size(); index++) {
            jdbcClient.sql("""
                    INSERT INTO moment_media(moment_id, media_id, position)
                    VALUES (:momentId, :mediaId, :position)
                    """)
                .param("momentId", id)
                .param("mediaId", ids.get(index))
                .param("position", index)
                .update();
        }
        return moment(id, actor);
    }

    List<SocialMomentResponse> moments(AuthenticatedUser actor) {
        return jdbcClient.sql("""
                SELECT id FROM moments
                WHERE user_id = :actorId OR EXISTS (
                    SELECT 1 FROM friendships
                    WHERE user_low_id = MIN(user_id, :actorId)
                      AND user_high_id = MAX(user_id, :actorId)
                )
                ORDER BY created_at DESC LIMIT 100
                """)
            .param("actorId", actor.id())
            .query((row, number) -> moment(row.getString("id"), actor))
            .list();
    }

    void deleteMoment(AuthenticatedUser actor, String momentId) {
        var owner = momentOwner(momentId);
        if (!owner.equals(actor.id()) && !actor.role().name().equals("ADMIN")) {
            throw new ResponseStatusException(FORBIDDEN, "You cannot delete this moment");
        }
        jdbcClient.sql("DELETE FROM moments WHERE id = :id").param("id", momentId).update();
    }

    void setLiked(AuthenticatedUser actor, String momentId, boolean liked) {
        requireVisibleMoment(actor.id(), momentId);
        if (liked) {
            jdbcClient.sql("""
                    INSERT OR IGNORE INTO moment_likes(moment_id, user_id, created_at)
                    VALUES (:momentId, :userId, :now)
                    """)
                .param("momentId", momentId)
                .param("userId", actor.id())
                .param("now", clock.millis())
                .update();
        } else {
            jdbcClient.sql("DELETE FROM moment_likes WHERE moment_id = :momentId AND user_id = :userId")
                .param("momentId", momentId)
                .param("userId", actor.id())
                .update();
        }
    }

    SocialCommentResponse comment(AuthenticatedUser actor, String momentId, String body) {
        var value = body == null ? "" : body.strip();
        if (value.isEmpty() || value.length() > 500) {
            throw new ResponseStatusException(BAD_REQUEST, "Comments must be 1-500 characters");
        }
        requireVisibleMoment(actor.id(), momentId);
        var id = UUID.randomUUID().toString();
        var createdAt = clock.millis();
        jdbcClient.sql("""
                INSERT INTO moment_comments(id, moment_id, user_id, body, created_at)
                VALUES (:id, :momentId, :userId, :body, :now)
                """)
            .param("id", id)
            .param("momentId", momentId)
            .param("userId", actor.id())
            .param("body", value)
            .param("now", createdAt)
            .update();
        return new SocialCommentResponse(id, profile(actor), value, createdAt);
    }

    private SocialUserResponse conversationUser(
        String userId, AuthenticatedUser actor, boolean friend
    ) {
        var last = jdbcClient.sql("""
                SELECT * FROM messages
                WHERE (sender_id = :actorId AND recipient_id = :peerId)
                   OR (sender_id = :peerId AND recipient_id = :actorId)
                ORDER BY created_at DESC, id DESC LIMIT 1
                """)
            .param("actorId", actor.id())
            .param("peerId", userId)
            .query((row, number) -> message(row, actor.id()))
            .optional()
            .orElse(null);
        var unread = jdbcClient.sql("""
                SELECT COUNT(*) FROM messages
                WHERE sender_id = :peerId AND recipient_id = :actorId
                  AND read_at IS NULL AND recalled_at IS NULL
                """)
            .param("peerId", userId)
            .param("actorId", actor.id())
            .query(Integer.class)
            .single();
        return user(userId, actor, friend, unread, last);
    }

    private SocialUserResponse user(
        String userId,
        AuthenticatedUser actor,
        Boolean friend,
        Integer unread,
        SocialMessageResponse lastMessage
    ) {
        return jdbcClient.sql("SELECT * FROM users WHERE id = :id AND enabled = 1")
            .param("id", userId)
            .query((row, number) -> {
                var avatar = row.getString("avatar");
                var preset = avatar != null && avatar.startsWith("preset:") ? avatar.substring(7) : null;
                var avatarURL = avatar != null && avatar.startsWith("upload:")
                    ? "/api/v1/avatars/" + userId + "?v=" + avatar.substring(7)
                    : null;
                var lastSeen = nullableLong(row, "last_seen_at");
                var lastLogin = actor.role().name().equals("ADMIN")
                    ? nullableLong(row, "last_login_at") : null;
                return new SocialUserResponse(
                    userId,
                    row.getString("username"),
                    row.getString("role"),
                    Optional.ofNullable(row.getString("display_name")).orElse(row.getString("username")),
                    Optional.ofNullable(row.getString("signature")).orElse(""),
                    preset,
                    avatarURL,
                    userId.equals(actor.id()) || lastSeen != null && clock.millis() - lastSeen <= ONLINE_WINDOW_MILLIS,
                    lastSeen,
                    lastLogin,
                    friend,
                    unread,
                    lastMessage
                );
            })
            .optional()
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "User not found"));
    }

    private SocialMessageResponse findMessage(String id, String actorId) {
        return jdbcClient.sql("SELECT * FROM messages WHERE id = :id")
            .param("id", id)
            .query((row, number) -> message(row, actorId))
            .optional()
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Message not found"));
    }

    @SuppressWarnings("unchecked")
    private SocialMessageResponse message(ResultSet row, String actorId) throws SQLException {
        Map<String, Object> payload = null;
        var rawPayload = row.getString("payload_json");
        if (rawPayload != null && !rawPayload.isBlank()) {
            try {
                payload = objectMapper.readValue(rawPayload, Map.class);
            } catch (JacksonException ignored) {
                payload = Collections.emptyMap();
            }
        }
        return new SocialMessageResponse(
            row.getString("id"),
            row.getString("sender_id"),
            row.getString("recipient_id"),
            row.getString("kind"),
            Optional.ofNullable(row.getString("text")).orElse(""),
            payload,
            row.getLong("created_at"),
            nullableLong(row, "recalled_at"),
            nullableLong(row, "read_at"),
            row.getString("sender_id").equals(actorId)
        );
    }

    private SocialMediaFile mapMedia(ResultSet row, int number) throws SQLException {
        return new SocialMediaFile(
            row.getString("id"), row.getString("user_id"), row.getString("kind"),
            row.getString("mime_type"), row.getString("original_name"),
            row.getString("storage_path"), row.getLong("size_bytes"),
            row.getString("group_id"), row.getString("component")
        );
    }

    private SocialMomentResponse moment(String id, AuthenticatedUser actor) {
        var row = jdbcClient.sql("SELECT * FROM moments WHERE id = :id")
            .param("id", id)
            .query((value, number) -> new MomentRow(
                value.getString("id"), value.getString("user_id"),
                value.getString("text"), value.getLong("created_at")
            ))
            .optional()
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Moment not found"));
        var media = jdbcClient.sql("""
                SELECT sm.* FROM moment_media mm
                JOIN social_media sm ON sm.id = mm.media_id
                WHERE mm.moment_id = :id ORDER BY mm.position
                """)
            .param("id", id)
            .query((value, number) -> mapMedia(value, number).response())
            .list();
        var likes = jdbcClient.sql("""
                SELECT user_id FROM moment_likes WHERE moment_id = :id ORDER BY created_at
                """)
            .param("id", id)
            .query((value, number) -> user(value.getString("user_id"), actor, null, null, null))
            .list();
        var comments = jdbcClient.sql("""
                SELECT * FROM moment_comments WHERE moment_id = :id ORDER BY created_at, id
                """)
            .param("id", id)
            .query((value, number) -> new SocialCommentResponse(
                value.getString("id"),
                user(value.getString("user_id"), actor, null, null, null),
                value.getString("body"),
                value.getLong("created_at")
            ))
            .list();
        return new SocialMomentResponse(
            id, user(row.userId(), actor, null, null, null), row.text(), row.createdAt(),
            media, likes, comments, likes.stream().anyMatch(value -> value.id().equals(actor.id()))
        );
    }

    private String momentOwner(String momentId) {
        return jdbcClient.sql("SELECT user_id FROM moments WHERE id = :id")
            .param("id", momentId)
            .query(String.class)
            .optional()
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Moment not found"));
    }

    private void requireVisibleMoment(String actorId, String momentId) {
        var owner = momentOwner(momentId);
        if (!owner.equals(actorId) && !isFriend(actorId, owner)) {
            throw new ResponseStatusException(FORBIDDEN, "Moment is not visible");
        }
    }

    private void requireUser(String userId) {
        if (jdbcClient.sql("SELECT COUNT(*) FROM users WHERE id = :id AND enabled = 1")
            .param("id", userId).query(Integer.class).single() != 1) {
            throw new ResponseStatusException(NOT_FOUND, "User not found");
        }
    }

    private boolean hasMessageHistory(String first, String second) {
        return jdbcClient.sql("""
                SELECT COUNT(*) FROM messages
                WHERE (sender_id = :first AND recipient_id = :second)
                   OR (sender_id = :second AND recipient_id = :first)
                """)
            .param("first", first)
            .param("second", second)
            .query(Integer.class)
            .single() > 0;
    }

    private boolean isFriend(String first, String second) {
        var pair = pair(first, second);
        return jdbcClient.sql("""
                SELECT COUNT(*) FROM friendships
                WHERE user_low_id = :low AND user_high_id = :high
                """)
            .param("low", pair[0])
            .param("high", pair[1])
            .query(Integer.class)
            .single() == 1;
    }

    private String json(Map<String, Object> value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JacksonException exception) {
            throw new ResponseStatusException(BAD_REQUEST, "Invalid message payload");
        }
    }

    private static String[] pair(String first, String second) {
        return first.compareTo(second) < 0
            ? new String[]{first, second}
            : new String[]{second, first};
    }

    private static Long nullableLong(ResultSet row, String name) throws SQLException {
        var value = row.getLong(name);
        return row.wasNull() ? null : value;
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }

    private static boolean blank(Object value) {
        return value == null || value.toString().isBlank();
    }

    private record MomentRow(String id, String userId, String text, long createdAt) {
    }
}
