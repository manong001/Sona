package cc.eu.sosee.sona.library;

import java.time.Clock;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class RecommendationPreferenceRepository {

    private final JdbcClient jdbcClient;
    private final Clock clock;

    RecommendationPreferenceRepository(JdbcClient jdbcClient, Clock clock) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
    }

    RecommendationPreferences preferences(String userId) {
        var enabled = jdbcClient.sql("""
                SELECT personalized_enabled FROM recommendation_settings
                WHERE user_id = :userId
                """)
            .param("userId", userId)
            .query(Integer.class)
            .optional()
            .map(value -> value == 1)
            .orElse(true);
        return new RecommendationPreferences(enabled, feedback(userId));
    }

    boolean personalizedEnabled(String userId) {
        return preferences(userId).personalizedEnabled();
    }

    void setPersonalizedEnabled(String userId, boolean enabled) {
        jdbcClient.sql("""
                INSERT INTO recommendation_settings(user_id, personalized_enabled, updated_at)
                VALUES (:userId, :enabled, :updatedAt)
                ON CONFLICT(user_id) DO UPDATE SET
                    personalized_enabled = excluded.personalized_enabled,
                    updated_at = excluded.updated_at
                """)
            .param("userId", userId)
            .param("enabled", enabled ? 1 : 0)
            .param("updatedAt", clock.millis())
            .update();
    }

    RecommendationFeedback add(
        String userId, FeedbackTargetType type, String targetValue, String displayValue
    ) {
        var normalized = normalize(targetValue);
        var existing = jdbcClient.sql("""
                SELECT * FROM recommendation_feedback
                WHERE user_id = :userId AND target_type = :targetType
                  AND target_value = :targetValue
                """)
            .param("userId", userId)
            .param("targetType", type.name())
            .param("targetValue", normalized)
            .query(RecommendationPreferenceRepository::mapFeedback)
            .optional();
        if (existing.isPresent()) return existing.get();

        var feedback = new RecommendationFeedback(
            UUID.randomUUID().toString(), type, normalized, displayValue.strip(), clock.millis()
        );
        jdbcClient.sql("""
                INSERT INTO recommendation_feedback(
                    id, user_id, target_type, target_value, display_value, created_at
                ) VALUES (
                    :id, :userId, :targetType, :targetValue, :displayValue, :createdAt
                )
                """)
            .param("id", feedback.id())
            .param("userId", userId)
            .param("targetType", type.name())
            .param("targetValue", feedback.targetValue())
            .param("displayValue", feedback.displayValue())
            .param("createdAt", feedback.createdAt())
            .update();
        return feedback;
    }

    boolean remove(String userId, String id) {
        return jdbcClient.sql("""
                DELETE FROM recommendation_feedback
                WHERE id = :id AND user_id = :userId
                """)
            .param("id", id)
            .param("userId", userId)
            .update() == 1;
    }

    void clear(String userId) {
        jdbcClient.sql("DELETE FROM recommendation_feedback WHERE user_id = :userId")
            .param("userId", userId)
            .update();
    }

    List<RecommendationFeedback> feedback(String userId) {
        return jdbcClient.sql("""
                SELECT * FROM recommendation_feedback
                WHERE user_id = :userId
                ORDER BY created_at DESC, id DESC
                """)
            .param("userId", userId)
            .query(RecommendationPreferenceRepository::mapFeedback)
            .list();
    }

    List<TrackRecord> allowed(String userId, List<TrackRecord> tracks) {
        var feedback = feedback(userId);
        if (feedback.isEmpty()) return tracks;
        return tracks.stream().filter(track -> feedback.stream().noneMatch(item -> rejects(item, track)))
            .toList();
    }

    List<AcousticTrackData> allowedAcoustic(String userId, List<AcousticTrackData> tracks) {
        var feedback = feedback(userId);
        if (feedback.isEmpty()) return tracks;
        return tracks.stream()
            .filter(item -> feedback.stream().noneMatch(value -> rejects(value, item.track())))
            .toList();
    }

    private boolean rejects(RecommendationFeedback feedback, TrackRecord track) {
        return switch (feedback.type()) {
            case TRACK -> normalize(track.id()).equals(feedback.targetValue());
            case ARTIST -> normalize(ArtistNames.canonical(track.artist()))
                .equals(feedback.targetValue());
            case GENRE -> {
                var primaryMatches = normalize(track.genre()).equals(feedback.targetValue());
                var relatedMatches = track.relatedGenres().stream()
                    .map(RecommendationPreferenceRepository::normalize)
                    .anyMatch(feedback.targetValue()::equals);
                yield primaryMatches || relatedMatches;
            }
        };
    }

    private static RecommendationFeedback mapFeedback(
        java.sql.ResultSet resultSet, int rowNumber
    ) throws java.sql.SQLException {
        return new RecommendationFeedback(
            resultSet.getString("id"),
            FeedbackTargetType.valueOf(resultSet.getString("target_type")),
            resultSet.getString("target_value"),
            resultSet.getString("display_value"),
            resultSet.getLong("created_at")
        );
    }

    private static String normalize(String value) {
        return value == null ? "" : value.strip().toLowerCase(Locale.ROOT);
    }

    enum FeedbackTargetType {
        TRACK, ARTIST, GENRE
    }

    record RecommendationFeedback(
        String id, FeedbackTargetType type, String targetValue, String displayValue, long createdAt
    ) {
    }

    record RecommendationPreferences(
        boolean personalizedEnabled, List<RecommendationFeedback> feedback
    ) {
    }
}
