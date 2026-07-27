package cc.eu.sosee.sona.download;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Clock;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.util.HtmlUtils;

@Repository
class PlaylistSubscriptionRepository {

    private final JdbcClient jdbcClient;
    private final Clock clock;

    PlaylistSubscriptionRepository(JdbcClient jdbcClient, Clock clock) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
    }

    Subscription create(
        String userId, String playlistId, String sourceUrl, String name,
        String poolType, boolean autoDownload, int syncIntervalHours
    ) {
        return create(
            userId, playlistId, sourceUrl, name, poolType,
            autoDownload, true, syncIntervalHours
        );
    }

    Subscription create(
        String userId, String playlistId, String sourceUrl, String name,
        String poolType, boolean autoDownload, boolean strictMode, int syncIntervalHours
    ) {
        var now = clock.millis();
        var id = UUID.randomUUID().toString();
        jdbcClient.sql("""
                INSERT INTO playlist_subscriptions (
                    id, user_id, playlist_id, source_url, name, pool_type, auto_download,
                    strict_mode, sync_interval_hours, enabled, created_at, updated_at
                ) VALUES (
                    :id, :userId, :playlistId, :sourceUrl, :name, :poolType, :autoDownload,
                    :strictMode, :syncIntervalHours, 1, :now, :now
                )
                """)
            .param("id", id)
            .param("userId", userId)
            .param("playlistId", playlistId)
            .param("sourceUrl", sourceUrl)
            .param("name", name)
            .param("poolType", poolType)
            .param("autoDownload", autoDownload ? 1 : 0)
            .param("strictMode", strictMode ? 1 : 0)
            .param("syncIntervalHours", syncIntervalHours)
            .param("now", now)
            .update();
        return find(userId, id).orElseThrow();
    }

    List<Subscription> findAll(String userId) {
        return select("WHERE subscriptions.user_id = :userId ORDER BY subscriptions.created_at DESC")
            .param("userId", userId)
            .query(this::map)
            .list();
    }

    Optional<Subscription> find(String userId, String id) {
        return select("WHERE subscriptions.user_id = :userId AND subscriptions.id = :id")
            .param("userId", userId)
            .param("id", id)
            .query(this::map)
            .optional();
    }

    List<String> matchedTrackIds(String subscriptionId) {
        return jdbcClient.sql("""
                WITH resolved_items AS (
                    SELECT items.position, (
                        SELECT tracks.id FROM tracks WHERE tracks.id = items.matched_track_id
                        UNION ALL
                        SELECT tracks.id FROM tracks
                        WHERE items.matched_track_id IS NULL
                          AND trim(tracks.title) COLLATE NOCASE = trim(items.title) COLLATE NOCASE
                          AND replace(trim(tracks.artist), '、', '/') COLLATE NOCASE =
                              replace(trim(items.artist), '、', '/') COLLATE NOCASE
                        ORDER BY id
                        LIMIT 1
                    ) AS track_id
                    FROM playlist_subscription_items items
                    WHERE items.subscription_id = :subscriptionId
                )
                SELECT track_id FROM resolved_items
                WHERE track_id IS NOT NULL
                ORDER BY position
                """)
            .param("subscriptionId", subscriptionId)
            .query(String.class)
            .list();
    }

    List<Item> findItems(String subscriptionId) {
        return jdbcClient.sql("""
                SELECT items.item_key, items.position, items.title, items.artist, items.album,
                    items.matched_track_id, items.last_seen_at,
                    CASE
                        WHEN EXISTS (SELECT 1 FROM tracks WHERE id = items.matched_track_id)
                            THEN 'MATCHED'
                        WHEN EXISTS (
                            SELECT 1 FROM tracks
                            WHERE trim(tracks.title) COLLATE NOCASE = trim(items.title) COLLATE NOCASE
                              AND replace(trim(tracks.artist), '、', '/') COLLATE NOCASE =
                                  replace(trim(items.artist), '、', '/') COLLATE NOCASE
                        ) THEN 'MATCHED'
                        WHEN EXISTS (
                            SELECT 1 FROM download_tasks
                            WHERE trim(download_tasks.title) COLLATE NOCASE = trim(items.title) COLLATE NOCASE
                              AND replace(trim(download_tasks.artist), '、', '/') COLLATE NOCASE =
                                  replace(trim(items.artist), '、', '/') COLLATE NOCASE
                              AND download_tasks.state IN ('QUEUED', 'RUNNING')
                        ) THEN 'DOWNLOADING'
                        WHEN items.state = 'SUGGESTED' THEN 'SUGGESTED'
                        ELSE 'MISSING'
                    END AS state
                FROM playlist_subscription_items items
                WHERE items.subscription_id = :subscriptionId
                ORDER BY items.position
                """)
            .param("subscriptionId", subscriptionId)
            .query(this::mapItem)
            .list();
    }

    Optional<Item> findItem(String userId, String subscriptionId, String itemKey) {
        return jdbcClient.sql("""
                SELECT items.* FROM playlist_subscription_items items
                JOIN playlist_subscriptions subscriptions ON subscriptions.id = items.subscription_id
                WHERE subscriptions.user_id = :userId
                  AND items.subscription_id = :subscriptionId
                  AND items.item_key = :itemKey
                """)
            .param("userId", userId)
            .param("subscriptionId", subscriptionId)
            .param("itemKey", itemKey)
            .query(this::mapItem)
            .optional();
    }

    boolean selectMatch(String userId, String subscriptionId, String itemKey, String trackId) {
        var selected = jdbcClient.sql("""
                UPDATE playlist_subscription_items
                SET matched_track_id = :trackId, state = 'MATCHED'
                WHERE subscription_id = :subscriptionId AND item_key = :itemKey
                  AND EXISTS (SELECT 1 FROM playlist_subscriptions
                      WHERE id = :subscriptionId AND user_id = :userId)
                  AND EXISTS (SELECT 1 FROM tracks WHERE id = :trackId)
                """)
            .param("trackId", trackId)
            .param("subscriptionId", subscriptionId)
            .param("itemKey", itemKey)
            .param("userId", userId)
            .update() == 1;
        if (selected) {
            updateVersionMatch(subscriptionId, itemKey, trackId);
        }
        return selected;
    }

    Optional<String> findRememberedMatch(String userId, String title, String artist) {
        return jdbcClient.sql("""
                SELECT choices.track_id
                FROM playlist_match_choices choices
                JOIN tracks ON tracks.id = choices.track_id
                WHERE choices.user_id = :userId
                  AND choices.normalized_title = :title
                  AND choices.normalized_artists = :artists
                """)
            .param("userId", userId)
            .param("title", PlaylistSubscriptionMatcher.normalizedText(title))
            .param("artists", PlaylistSubscriptionMatcher.normalizedArtists(artist))
            .query(String.class)
            .optional();
    }

    void rememberMatch(String userId, String title, String artist, String trackId) {
        jdbcClient.sql("""
                INSERT INTO playlist_match_choices (
                    user_id, normalized_title, normalized_artists, track_id, updated_at
                ) VALUES (
                    :userId, :title, :artists, :trackId, :now
                )
                ON CONFLICT(user_id, normalized_title, normalized_artists)
                DO UPDATE SET track_id = excluded.track_id, updated_at = excluded.updated_at
                """)
            .param("userId", userId)
            .param("title", PlaylistSubscriptionMatcher.normalizedText(title))
            .param("artists", PlaylistSubscriptionMatcher.normalizedArtists(artist))
            .param("trackId", trackId)
            .param("now", clock.millis())
            .update();
    }

    boolean bindDownloadedTrack(
        String playlistId, String title, String artist, String trackId
    ) {
        var bound = jdbcClient.sql("""
                UPDATE playlist_subscription_items
                SET matched_track_id = :trackId, state = 'MATCHED'
                WHERE rowid = (
                    SELECT items.rowid
                    FROM playlist_subscription_items items
                    JOIN playlist_subscriptions subscriptions
                      ON subscriptions.id = items.subscription_id
                    WHERE subscriptions.playlist_id = :playlistId
                      AND items.matched_track_id IS NULL
                      AND trim(items.title) COLLATE NOCASE = trim(:title) COLLATE NOCASE
                      AND replace(trim(items.artist), '、', '/') COLLATE NOCASE =
                          replace(trim(:artist), '、', '/') COLLATE NOCASE
                      AND EXISTS (
                          SELECT 1 FROM playlist_tracks
                          WHERE playlist_id = :playlistId AND track_id = :trackId
                      )
                      AND NOT EXISTS (
                          SELECT 1 FROM playlist_subscription_items other
                          WHERE other.subscription_id = items.subscription_id
                            AND other.matched_track_id = :trackId
                      )
                    ORDER BY items.position
                    LIMIT 1
                )
                """)
            .param("playlistId", playlistId)
            .param("title", title.strip())
            .param("artist", artist.strip())
            .param("trackId", trackId)
            .update() == 1;
        if (bound) {
            jdbcClient.sql("""
                    UPDATE playlist_subscription_version_items
                    SET matched_track_id = :trackId
                    WHERE item_key = (
                        SELECT items.item_key
                        FROM playlist_subscription_items items
                        JOIN playlist_subscriptions subscriptions
                          ON subscriptions.id = items.subscription_id
                        WHERE subscriptions.playlist_id = :playlistId
                          AND items.matched_track_id = :trackId
                        ORDER BY items.position
                        LIMIT 1
                    )
                    AND version_id IN (
                        SELECT versions.id
                        FROM playlist_subscription_versions versions
                        JOIN playlist_subscriptions subscriptions
                          ON subscriptions.id = versions.subscription_id
                        WHERE subscriptions.playlist_id = :playlistId
                    )
                    """)
                .param("trackId", trackId)
                .param("playlistId", playlistId)
                .update();
        }
        return bound;
    }

    void updateItemState(String subscriptionId, String itemKey, String state) {
        jdbcClient.sql("""
                UPDATE playlist_subscription_items SET state = :state
                WHERE subscription_id = :subscriptionId AND item_key = :itemKey
                """)
            .param("state", state)
            .param("subscriptionId", subscriptionId)
            .param("itemKey", itemKey)
            .update();
    }

    List<Subscription> findDue() {
        var now = clock.millis();
        return select("""
                WHERE subscriptions.enabled = 1
                  AND (subscriptions.last_synced_at IS NULL
                    OR subscriptions.last_synced_at + subscriptions.sync_interval_hours * 3600000 <= :now)
                ORDER BY COALESCE(subscriptions.last_synced_at, 0), subscriptions.created_at
                """)
            .param("now", now)
            .query(this::map)
            .list();
    }

    List<Subscription> findAllEnabled() {
        return select("""
                WHERE subscriptions.enabled = 1
                ORDER BY subscriptions.created_at
                """)
            .query(this::map)
            .list();
    }

    @Transactional
    void replaceItems(String subscriptionId, List<Item> items) {
        jdbcClient.sql("DELETE FROM playlist_subscription_items WHERE subscription_id = :id")
            .param("id", subscriptionId)
            .update();
        for (var item : items) {
            jdbcClient.sql("""
                    INSERT INTO playlist_subscription_items (
                        subscription_id, item_key, position, title, artist, album,
                        matched_track_id, state, last_seen_at
                    ) VALUES (
                        :subscriptionId, :itemKey, :position, :title, :artist, :album,
                        :matchedTrackId, :state, :lastSeenAt
                    )
                    """)
                .param("subscriptionId", subscriptionId)
                .param("itemKey", item.itemKey())
                .param("position", item.position())
                .param("title", item.title())
                .param("artist", item.artist())
                .param("album", item.album())
                .param("matchedTrackId", item.matchedTrackId())
                .param("state", item.state())
                .param("lastSeenAt", item.lastSeenAt())
                .update();
        }
    }

    @Transactional
    Version saveVersion(
        String subscriptionId, String name, String artworkHash, List<Item> items
    ) {
        var contentHash = versionContentHash(name, artworkHash, items);
        var latest = latestVersion(subscriptionId);
        if (latest.isPresent() && latest.get().contentHash().equals(contentHash)) {
            updateVersionMatches(subscriptionId, items);
            return version(latest.get().id()).orElseThrow();
        }

        var id = UUID.randomUUID().toString();
        var versionNumber = latest.map(value -> value.versionNumber() + 1).orElse(1);
        var now = clock.millis();
        jdbcClient.sql("""
                INSERT INTO playlist_subscription_versions(
                    id, subscription_id, version_number, name, artwork_hash,
                    content_hash, created_at
                ) VALUES (
                    :id, :subscriptionId, :versionNumber, :name, :artworkHash,
                    :contentHash, :createdAt
                )
                """)
            .param("id", id)
            .param("subscriptionId", subscriptionId)
            .param("versionNumber", versionNumber)
            .param("name", name)
            .param("artworkHash", artworkHash)
            .param("contentHash", contentHash)
            .param("createdAt", now)
            .update();
        for (var item : items) {
            jdbcClient.sql("""
                    INSERT INTO playlist_subscription_version_items(
                        version_id, item_key, position, title, artist, album, matched_track_id
                    ) VALUES (
                        :versionId, :itemKey, :position, :title, :artist, :album, :matchedTrackId
                    )
                    """)
                .param("versionId", id)
                .param("itemKey", item.itemKey())
                .param("position", item.position())
                .param("title", item.title())
                .param("artist", item.artist())
                .param("album", item.album())
                .param("matchedTrackId", item.matchedTrackId())
                .update();
        }
        jdbcClient.sql("""
                UPDATE playlist_subscriptions
                SET latest_version_id = :versionId,
                    selected_version_id = CASE
                        WHEN follow_latest = 1 OR selected_version_id IS NULL THEN :versionId
                        ELSE selected_version_id
                    END,
                    updated_at = :now
                WHERE id = :subscriptionId
                """)
            .param("versionId", id)
            .param("subscriptionId", subscriptionId)
            .param("now", now)
            .update();
        updateVersionMatches(subscriptionId, items);
        return version(id).orElseThrow();
    }

    List<Version> findVersions(String userId, String subscriptionId) {
        return jdbcClient.sql("""
                SELECT versions.*,
                    (SELECT COUNT(*) FROM playlist_subscription_version_items items
                     WHERE items.version_id = versions.id) AS item_count,
                    versions.id = subscriptions.selected_version_id AS selected,
                    versions.id = subscriptions.latest_version_id AS latest
                FROM playlist_subscription_versions versions
                JOIN playlist_subscriptions subscriptions
                  ON subscriptions.id = versions.subscription_id
                WHERE subscriptions.user_id = :userId
                  AND subscriptions.id = :subscriptionId
                ORDER BY versions.version_number DESC
                """)
            .param("userId", userId)
            .param("subscriptionId", subscriptionId)
            .query(this::mapVersion)
            .list();
    }

    Optional<VersionSnapshot> selectVersion(
        String userId, String subscriptionId, int versionNumber
    ) {
        var versionId = jdbcClient.sql("""
                SELECT versions.id
                FROM playlist_subscription_versions versions
                JOIN playlist_subscriptions subscriptions
                  ON subscriptions.id = versions.subscription_id
                WHERE subscriptions.user_id = :userId
                  AND subscriptions.id = :subscriptionId
                  AND versions.version_number = :versionNumber
                """)
            .param("userId", userId)
            .param("subscriptionId", subscriptionId)
            .param("versionNumber", versionNumber)
            .query(String.class)
            .optional();
        if (versionId.isEmpty()) {
            return Optional.empty();
        }
        jdbcClient.sql("""
                UPDATE playlist_subscriptions
                SET selected_version_id = :versionId, follow_latest = 0, updated_at = :now
                WHERE id = :subscriptionId AND user_id = :userId
                """)
            .param("versionId", versionId.get())
            .param("subscriptionId", subscriptionId)
            .param("userId", userId)
            .param("now", clock.millis())
            .update();
        return snapshot(versionId.get());
    }

    Optional<VersionSnapshot> followLatest(String userId, String subscriptionId) {
        var versionId = jdbcClient.sql("""
                SELECT latest_version_id FROM playlist_subscriptions
                WHERE id = :subscriptionId AND user_id = :userId
                  AND latest_version_id IS NOT NULL
                """)
            .param("subscriptionId", subscriptionId)
            .param("userId", userId)
            .query(String.class)
            .optional();
        if (versionId.isEmpty()) {
            return Optional.empty();
        }
        jdbcClient.sql("""
                UPDATE playlist_subscriptions
                SET selected_version_id = latest_version_id, follow_latest = 1, updated_at = :now
                WHERE id = :subscriptionId AND user_id = :userId
                """)
            .param("subscriptionId", subscriptionId)
            .param("userId", userId)
            .param("now", clock.millis())
            .update();
        return snapshot(versionId.get());
    }

    Optional<VersionSnapshot> selectedVersion(String subscriptionId) {
        return jdbcClient.sql("""
                SELECT selected_version_id FROM playlist_subscriptions
                WHERE id = :subscriptionId AND selected_version_id IS NOT NULL
                """)
            .param("subscriptionId", subscriptionId)
            .query(String.class)
            .optional()
            .flatMap(this::snapshot);
    }

    Optional<Version> findVersion(
        String userId, String subscriptionId, int versionNumber
    ) {
        return jdbcClient.sql("""
                SELECT versions.*,
                    (SELECT COUNT(*) FROM playlist_subscription_version_items items
                     WHERE items.version_id = versions.id) AS item_count,
                    versions.id = subscriptions.selected_version_id AS selected,
                    versions.id = subscriptions.latest_version_id AS latest
                FROM playlist_subscription_versions versions
                JOIN playlist_subscriptions subscriptions
                  ON subscriptions.id = versions.subscription_id
                WHERE subscriptions.user_id = :userId
                  AND subscriptions.id = :subscriptionId
                  AND versions.version_number = :versionNumber
                """)
            .param("userId", userId)
            .param("subscriptionId", subscriptionId)
            .param("versionNumber", versionNumber)
            .query(this::mapVersion)
            .optional();
    }

    List<String> selectedMatchedTrackIds(String subscriptionId) {
        var selected = selectedVersion(subscriptionId);
        if (selected.isEmpty()) {
            return matchedTrackIds(subscriptionId);
        }
        return jdbcClient.sql("""
                WITH resolved_items AS (
                    SELECT items.position, (
                        SELECT tracks.id FROM tracks WHERE tracks.id = items.matched_track_id
                        UNION ALL
                        SELECT tracks.id FROM tracks
                        WHERE items.matched_track_id IS NULL
                          AND trim(tracks.title) COLLATE NOCASE = trim(items.title) COLLATE NOCASE
                          AND replace(trim(tracks.artist), '、', '/') COLLATE NOCASE =
                              replace(trim(items.artist), '、', '/') COLLATE NOCASE
                        ORDER BY id
                        LIMIT 1
                    ) AS track_id
                    FROM playlist_subscription_version_items items
                    WHERE items.version_id = :versionId
                )
                SELECT track_id FROM resolved_items
                WHERE track_id IS NOT NULL
                ORDER BY position
                """)
            .param("versionId", selected.get().version().id())
            .query(String.class)
            .list();
    }

    private void updateVersionMatches(String subscriptionId, List<Item> items) {
        for (var item : items) {
            if (item.matchedTrackId() == null) {
                continue;
            }
            updateVersionMatch(subscriptionId, item.itemKey(), item.matchedTrackId());
        }
    }

    private void updateVersionMatch(String subscriptionId, String itemKey, String trackId) {
        jdbcClient.sql("""
                UPDATE playlist_subscription_version_items
                SET matched_track_id = :trackId
                WHERE item_key = :itemKey
                  AND version_id IN (
                      SELECT id FROM playlist_subscription_versions
                      WHERE subscription_id = :subscriptionId
                  )
                """)
            .param("trackId", trackId)
            .param("itemKey", itemKey)
            .param("subscriptionId", subscriptionId)
            .update();
    }

    private Optional<StoredVersion> latestVersion(String subscriptionId) {
        return jdbcClient.sql("""
                SELECT id, version_number, content_hash
                FROM playlist_subscription_versions
                WHERE subscription_id = :subscriptionId
                ORDER BY version_number DESC
                LIMIT 1
                """)
            .param("subscriptionId", subscriptionId)
            .query((resultSet, rowNumber) -> new StoredVersion(
                resultSet.getString("id"), resultSet.getInt("version_number"),
                resultSet.getString("content_hash")
            ))
            .optional();
    }

    private Optional<Version> version(String id) {
        return jdbcClient.sql("""
                SELECT versions.*,
                    (SELECT COUNT(*) FROM playlist_subscription_version_items items
                     WHERE items.version_id = versions.id) AS item_count,
                    versions.id = subscriptions.selected_version_id AS selected,
                    versions.id = subscriptions.latest_version_id AS latest
                FROM playlist_subscription_versions versions
                JOIN playlist_subscriptions subscriptions
                  ON subscriptions.id = versions.subscription_id
                WHERE versions.id = :id
                """)
            .param("id", id)
            .query(this::mapVersion)
            .optional();
    }

    private Optional<VersionSnapshot> snapshot(String versionId) {
        return version(versionId).map(value -> new VersionSnapshot(
            value,
            jdbcClient.sql("""
                    SELECT item_key, position, title, artist, album, matched_track_id,
                           'MISSING' AS state, 0 AS last_seen_at
                    FROM playlist_subscription_version_items
                    WHERE version_id = :versionId
                    ORDER BY position
                    """)
                .param("versionId", versionId)
                .query(this::mapItem)
                .list()
        ));
    }

    private Version mapVersion(ResultSet resultSet, int rowNumber) throws SQLException {
        return new Version(
            resultSet.getString("id"), resultSet.getInt("version_number"),
            decodeHtml(resultSet.getString("name")), resultSet.getString("artwork_hash"),
            resultSet.getString("content_hash"), resultSet.getInt("item_count"),
            resultSet.getLong("created_at"), resultSet.getBoolean("selected"),
            resultSet.getBoolean("latest")
        );
    }

    private String versionContentHash(String name, String artworkHash, List<Item> items) {
        try {
            var digest = MessageDigest.getInstance("SHA-256");
            addDigestValue(digest, name);
            addDigestValue(digest, artworkHash);
            for (var item : items) {
                addDigestValue(digest, Integer.toString(item.position()));
                addDigestValue(digest, item.itemKey());
                addDigestValue(digest, item.title());
                addDigestValue(digest, item.artist());
                addDigestValue(digest, item.album());
            }
            return HexFormat.of().formatHex(digest.digest());
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException(exception);
        }
    }

    private void addDigestValue(MessageDigest digest, String value) {
        var bytes = value == null ? new byte[0] : value.getBytes(StandardCharsets.UTF_8);
        digest.update(Integer.toString(bytes.length).getBytes(StandardCharsets.UTF_8));
        digest.update((byte) ':');
        digest.update(bytes);
    }

    void markSynced(String id) {
        var now = clock.millis();
        jdbcClient.sql("""
                UPDATE playlist_subscriptions
                SET last_synced_at = :now, last_error = NULL, updated_at = :now
                WHERE id = :id
                """)
            .param("now", now)
            .param("id", id)
            .update();
    }

    void rename(String id, String name) {
        jdbcClient.sql("""
                UPDATE playlist_subscriptions SET name = :name, updated_at = :now WHERE id = :id
                """)
            .param("name", name)
            .param("now", clock.millis())
            .param("id", id)
            .update();
    }

    void retarget(String id, String playlistId) {
        jdbcClient.sql("""
                UPDATE playlist_subscriptions
                SET playlist_id = :playlistId, updated_at = :now
                WHERE id = :id
                """)
            .param("playlistId", playlistId)
            .param("now", clock.millis())
            .param("id", id)
            .update();
    }

    void updateStrictMode(String id, boolean strictMode) {
        jdbcClient.sql("""
                UPDATE playlist_subscriptions
                SET strict_mode = :strictMode, updated_at = :now
                WHERE id = :id
                """)
            .param("strictMode", strictMode ? 1 : 0)
            .param("now", clock.millis())
            .param("id", id)
            .update();
    }

    void updateSettings(
        String id, String name, String poolType, boolean autoDownload,
        boolean strictMode, int syncIntervalHours
    ) {
        jdbcClient.sql("""
                UPDATE playlist_subscriptions
                SET name = :name, pool_type = :poolType,
                    auto_download = :autoDownload, strict_mode = :strictMode,
                    sync_interval_hours = :syncIntervalHours, updated_at = :now
                WHERE id = :id
                """)
            .param("name", name)
            .param("poolType", poolType)
            .param("autoDownload", autoDownload ? 1 : 0)
            .param("strictMode", strictMode ? 1 : 0)
            .param("syncIntervalHours", syncIntervalHours)
            .param("now", clock.millis())
            .param("id", id)
            .update();
    }

    void updateArtwork(
        String id, String artworkUrl, String artworkHash, boolean versioningEnabled
    ) {
        jdbcClient.sql("""
                UPDATE playlist_subscriptions
                SET artwork_url = :artworkUrl, pending_artwork_hash = :artworkHash,
                    updated_at = :now
                WHERE id = :id
                """)
            .param("artworkUrl", artworkUrl)
            .param(
                "artworkHash",
                versioningEnabled ? (artworkHash == null ? "" : artworkHash) : null
            )
            .param("now", clock.millis())
            .param("id", id)
            .update();
    }

    String pendingArtworkHash(String id) {
        return jdbcClient.sql("""
                SELECT pending_artwork_hash FROM playlist_subscriptions WHERE id = :id
                """)
            .param("id", id)
            .query(String.class)
            .optional()
            .filter(value -> !value.isBlank())
            .orElse(null);
    }

    boolean hasPendingArtworkState(String id) {
        return jdbcClient.sql("""
                SELECT COUNT(*) FROM playlist_subscriptions
                WHERE id = :id AND pending_artwork_hash IS NOT NULL
                """)
            .param("id", id)
            .query(Integer.class)
            .single() == 1;
    }

    void markFailed(String id, String message) {
        jdbcClient.sql("""
                UPDATE playlist_subscriptions SET last_error = :message, updated_at = :now
                WHERE id = :id
                """)
            .param("message", message)
            .param("now", clock.millis())
            .param("id", id)
            .update();
    }

    @Transactional
    boolean delete(String userId, String id) {
        var deleted = jdbcClient.sql("""
                DELETE FROM playlist_subscriptions WHERE id = :id AND user_id = :userId
                """)
            .param("id", id)
            .param("userId", userId)
            .update() == 1;
        if (deleted) {
            jdbcClient.sql("DELETE FROM playlist_subscription_items WHERE subscription_id = :id")
                .param("id", id)
                .update();
        }
        return deleted;
    }

    private JdbcClient.StatementSpec select(String suffix) {
        return jdbcClient.sql("""
            WITH item_states AS (
                SELECT items.subscription_id,
                    CASE
                        WHEN EXISTS (
                            SELECT 1 FROM tracks WHERE tracks.id = items.matched_track_id
                        ) THEN 'MATCHED'
                        WHEN EXISTS (
                            SELECT 1 FROM tracks
                            WHERE trim(tracks.title) COLLATE NOCASE =
                                  trim(items.title) COLLATE NOCASE
                              AND replace(trim(tracks.artist), '、', '/') COLLATE NOCASE =
                                  replace(trim(items.artist), '、', '/') COLLATE NOCASE
                        ) THEN 'MATCHED'
                        WHEN EXISTS (
                            SELECT 1 FROM download_tasks tasks
                            WHERE trim(tasks.title) COLLATE NOCASE =
                                  trim(items.title) COLLATE NOCASE
                              AND replace(trim(tasks.artist), '、', '/') COLLATE NOCASE =
                                  replace(trim(items.artist), '、', '/') COLLATE NOCASE
                              AND tasks.state = 'RUNNING'
                        ) THEN 'RUNNING'
                        WHEN EXISTS (
                            SELECT 1 FROM download_tasks tasks
                            WHERE trim(tasks.title) COLLATE NOCASE =
                                  trim(items.title) COLLATE NOCASE
                              AND replace(trim(tasks.artist), '、', '/') COLLATE NOCASE =
                                  replace(trim(items.artist), '、', '/') COLLATE NOCASE
                              AND tasks.state = 'QUEUED'
                        ) THEN 'QUEUED'
                        WHEN items.state = 'SUGGESTED' THEN 'SUGGESTED'
                        ELSE 'MISSING'
                    END AS state
                FROM playlist_subscription_items items
            )
            SELECT subscriptions.*, users.username,
                COALESCE((
                    SELECT version_number FROM playlist_subscription_versions
                    WHERE id = subscriptions.latest_version_id
                ), 0) AS latest_version_number,
                COALESCE((
                    SELECT version_number FROM playlist_subscription_versions
                    WHERE id = subscriptions.selected_version_id
                ), 0) AS selected_version_number,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id) AS item_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id AND items.state = 'MATCHED') AS matched_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id AND items.state = 'MISSING') AS missing_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id AND items.state = 'SUGGESTED') AS suggested_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id
                      AND items.state IN ('QUEUED', 'RUNNING')) AS downloading_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id AND items.state = 'QUEUED') AS queued_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id AND items.state = 'RUNNING') AS running_count
            FROM playlist_subscriptions subscriptions
            JOIN users ON users.id = subscriptions.user_id
            """ + suffix);
    }

    private Subscription map(ResultSet resultSet, int rowNumber) throws SQLException {
        var lastSyncedAt = resultSet.getLong("last_synced_at");
        Long nullableLastSyncedAt = resultSet.wasNull() ? null : lastSyncedAt;
        return new Subscription(
            resultSet.getString("id"), resultSet.getString("user_id"),
            resultSet.getString("username"), resultSet.getString("playlist_id"),
            resultSet.getString("source_url"), decodeHtml(resultSet.getString("name")),
            resultSet.getString("pool_type"), resultSet.getInt("auto_download") == 1,
            resultSet.getInt("strict_mode") == 1, resultSet.getInt("sync_interval_hours"),
            resultSet.getInt("enabled") == 1,
            nullableLastSyncedAt, resultSet.getString("last_error"),
            resultSet.getLong("created_at"), resultSet.getLong("updated_at"),
            resultSet.getInt("item_count"), resultSet.getInt("matched_count"),
            resultSet.getInt("missing_count"), resultSet.getInt("downloading_count"),
            resultSet.getInt("queued_count"), resultSet.getInt("running_count"),
            resultSet.getInt("suggested_count"),
            resultSet.getInt("latest_version_number"),
            resultSet.getInt("selected_version_number"),
            resultSet.getInt("follow_latest") == 1
        );
    }

    private Item mapItem(ResultSet resultSet, int rowNumber) throws SQLException {
        return new Item(
            resultSet.getString("item_key"), resultSet.getInt("position"),
            decodeHtml(resultSet.getString("title")), decodeHtml(resultSet.getString("artist")),
            decodeHtml(resultSet.getString("album")), resultSet.getString("matched_track_id"),
            resultSet.getString("state"), resultSet.getLong("last_seen_at")
        );
    }

    private String decodeHtml(String value) {
        return value == null ? null : HtmlUtils.htmlUnescape(value);
    }

    record Subscription(
        String id, String userId, String username, String playlistId, String sourceUrl,
        String name, String poolType, boolean autoDownload, boolean strictMode,
        int syncIntervalHours,
        boolean enabled, Long lastSyncedAt, String lastError, long createdAt, long updatedAt,
        int itemCount, int matchedCount, int missingCount, int downloadingCount,
        int queuedCount, int runningCount, int suggestedCount,
        int latestVersionNumber, int selectedVersionNumber, boolean followingLatest
    ) {
        Subscription(
            String id, String userId, String username, String playlistId, String sourceUrl,
            String name, String poolType, boolean autoDownload, boolean strictMode,
            int syncIntervalHours,
            boolean enabled, Long lastSyncedAt, String lastError, long createdAt, long updatedAt,
            int itemCount, int matchedCount, int missingCount, int downloadingCount,
            int queuedCount, int runningCount, int suggestedCount
        ) {
            this(
                id, userId, username, playlistId, sourceUrl, name, poolType, autoDownload,
                strictMode, syncIntervalHours, enabled, lastSyncedAt, lastError,
                createdAt, updatedAt, itemCount, matchedCount, missingCount, downloadingCount,
                queuedCount, runningCount, suggestedCount, 0, 0, true
            );
        }

        Subscription(
            String id, String userId, String username, String playlistId, String sourceUrl,
            String name, String poolType, boolean autoDownload, int syncIntervalHours,
            boolean enabled, Long lastSyncedAt, String lastError, long createdAt, long updatedAt,
            int itemCount, int matchedCount, int missingCount, int downloadingCount,
            int queuedCount, int runningCount, int suggestedCount
        ) {
            this(
                id, userId, username, playlistId, sourceUrl, name, poolType, autoDownload,
                true, syncIntervalHours, enabled, lastSyncedAt, lastError, createdAt, updatedAt,
                itemCount, matchedCount, missingCount, downloadingCount,
                queuedCount, runningCount, suggestedCount, 0, 0, true
            );
        }

        Subscription(
            String id, String userId, String username, String playlistId, String sourceUrl,
            String name, String poolType, boolean autoDownload, int syncIntervalHours,
            boolean enabled, Long lastSyncedAt, String lastError, long createdAt, long updatedAt,
            int itemCount, int matchedCount, int missingCount, int downloadingCount
        ) {
            this(
                id, userId, username, playlistId, sourceUrl, name, poolType, autoDownload,
                true, syncIntervalHours, enabled, lastSyncedAt, lastError, createdAt, updatedAt,
                itemCount, matchedCount, missingCount, downloadingCount,
                0, 0, 0, 0, 0, true
            );
        }
    }

    record Item(
        String itemKey, int position, String title, String artist, String album,
        String matchedTrackId, String state, long lastSeenAt
    ) {
    }

    record Version(
        String id, int versionNumber, String name, String artworkHash, String contentHash,
        int itemCount, long createdAt, boolean selected, boolean latest
    ) {
        boolean hasArtwork() {
            return artworkHash != null && !artworkHash.isBlank();
        }
    }

    record VersionSnapshot(Version version, List<Item> items) {
    }

    private record StoredVersion(String id, int versionNumber, String contentHash) {
    }
}
