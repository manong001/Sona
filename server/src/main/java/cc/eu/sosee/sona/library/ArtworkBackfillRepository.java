package cc.eu.sosee.sona.library;

import java.nio.file.Path;
import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
class ArtworkBackfillRepository {

    private final JdbcClient jdbcClient;

    ArtworkBackfillRepository(JdbcClient jdbcClient) {
        this.jdbcClient = jdbcClient;
    }

    List<Candidate> findDue(long now, int limit) {
        return jdbcClient.sql("""
                SELECT tracks.*, COALESCE(attempts.attempts, 0) AS artwork_attempts
                FROM tracks
                LEFT JOIN artwork_backfill_attempts attempts ON attempts.track_id = tracks.id
                WHERE tracks.artwork_path IS NULL
                  AND COALESCE(attempts.retry_at, 0) <= :now
                ORDER BY COALESCE(attempts.retry_at, 0), tracks.created_at, tracks.id
                LIMIT :limit
                """)
            .param("now", now)
            .param("limit", limit)
            .query((resultSet, rowNumber) -> new Candidate(
                JdbcTrackStore.mapTrack(resultSet, rowNumber),
                resultSet.getInt("artwork_attempts")
            ))
            .list();
    }

    @Transactional
    void markSucceeded(String trackId, Path artworkPath) {
        jdbcClient.sql("""
                UPDATE tracks
                SET artwork_path = :artworkPath, artwork_source = 'SCRAPED'
                WHERE id = :trackId AND artwork_path IS NULL
                """)
            .param("artworkPath", artworkPath.toString())
            .param("trackId", trackId)
            .update();
        jdbcClient.sql("DELETE FROM artwork_backfill_attempts WHERE track_id = :trackId")
            .param("trackId", trackId)
            .update();
    }

    void markFailed(
        String trackId, int attempts, long retryAt, String error, long updatedAt
    ) {
        jdbcClient.sql("""
                INSERT INTO artwork_backfill_attempts(
                    track_id, attempts, retry_at, last_error, updated_at
                ) VALUES (
                    :trackId, :attempts, :retryAt, :error, :updatedAt
                )
                ON CONFLICT(track_id) DO UPDATE SET
                    attempts = excluded.attempts,
                    retry_at = excluded.retry_at,
                    last_error = excluded.last_error,
                    updated_at = excluded.updated_at
                """)
            .param("trackId", trackId)
            .param("attempts", attempts)
            .param("retryAt", retryAt)
            .param("error", error)
            .param("updatedAt", updatedAt)
            .update();
    }

    record Candidate(TrackRecord track, int attempts) {
    }
}
