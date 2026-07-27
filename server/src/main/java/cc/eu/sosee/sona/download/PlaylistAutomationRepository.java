package cc.eu.sosee.sona.download;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Clock;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
class PlaylistAutomationRepository {

    private final JdbcClient jdbcClient;
    private final Clock clock;

    PlaylistAutomationRepository(JdbcClient jdbcClient, Clock clock) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
    }

    boolean isDue(String subscriptionId, int intervalHours) {
        var latest = jdbcClient.sql("""
                SELECT MAX(created_at) FROM playlist_automation_runs
                WHERE subscription_id = :subscriptionId
                """)
            .param("subscriptionId", subscriptionId)
            .query(Long.class)
            .optional()
            .orElse(null);
        return latest == null || latest + intervalHours * 3_600_000L <= clock.millis();
    }

    String start(PlaylistSubscriptionRepository.Subscription subscription) {
        var id = UUID.randomUUID().toString();
        jdbcClient.sql("""
                INSERT INTO playlist_automation_runs (
                    id, subscription_id, user_id, playlist_name, state, created_at
                ) VALUES (
                    :id, :subscriptionId, :userId, :playlistName, 'PREPARING', :createdAt
                )
                """)
            .param("id", id)
            .param("subscriptionId", subscription.id())
            .param("userId", subscription.userId())
            .param("playlistName", subscription.name())
            .param("createdAt", clock.millis())
            .update();
        return id;
    }

    @Transactional
    void waitForDownloads(String runId, int matchedCount, List<DownloadTask> tasks) {
        jdbcClient.sql("""
                UPDATE playlist_automation_runs
                SET matched_count = :matchedCount,
                    queued_count = :queuedCount,
                    state = :state
                WHERE id = :id
                """)
            .param("matchedCount", matchedCount)
            .param("queuedCount", tasks.size())
            .param("state", tasks.isEmpty() ? "COMPLETED" : "WAITING_DOWNLOADS")
            .param("id", runId)
            .update();
        for (var task : tasks) {
            jdbcClient.sql("""
                    INSERT INTO playlist_automation_run_tasks (
                        run_id, task_id, title, artist
                    ) VALUES (:runId, :taskId, :title, :artist)
                    """)
                .param("runId", runId)
                .param("taskId", task.id())
                .param("title", task.title())
                .param("artist", task.artist())
                .update();
        }
        if (tasks.isEmpty()) {
            complete(runId);
        }
    }

    void cancel(String runId) {
        jdbcClient.sql("DELETE FROM playlist_automation_runs WHERE id = :id")
            .param("id", runId)
            .update();
    }

    void fail(String runId, String error) {
        jdbcClient.sql("""
                UPDATE playlist_automation_runs
                SET state = 'FAILED', error = :error, completed_at = :completedAt
                WHERE id = :id
                """)
            .param("error", error)
            .param("completedAt", clock.millis())
            .param("id", runId)
            .update();
    }

    List<Run> pending() {
        return jdbcClient.sql("""
                SELECT id, subscription_id, user_id, playlist_name,
                       matched_count, queued_count, state, error,
                       created_at, completed_at
                FROM playlist_automation_runs
                WHERE state = 'WAITING_DOWNLOADS'
                ORDER BY created_at
                """)
            .query(this::mapRun)
            .list();
    }

    List<RunTask> tasks(String runId) {
        return jdbcClient.sql("""
                SELECT run_tasks.task_id, run_tasks.title, run_tasks.artist,
                       download_tasks.state, download_tasks.message
                FROM playlist_automation_run_tasks run_tasks
                LEFT JOIN download_tasks ON download_tasks.id = run_tasks.task_id
                WHERE run_tasks.run_id = :runId
                ORDER BY run_tasks.rowid
                """)
            .param("runId", runId)
            .query((resultSet, rowNumber) -> new RunTask(
                resultSet.getString("task_id"),
                resultSet.getString("title"),
                resultSet.getString("artist"),
                resultSet.getString("state"),
                resultSet.getString("message")
            ))
            .list();
    }

    void complete(String runId) {
        jdbcClient.sql("""
                UPDATE playlist_automation_runs
                SET state = 'COMPLETED', completed_at = :completedAt
                WHERE id = :id
                """)
            .param("completedAt", clock.millis())
            .param("id", runId)
            .update();
    }

    private Run mapRun(ResultSet resultSet, int rowNumber) throws SQLException {
        var completedAt = resultSet.getObject("completed_at");
        return new Run(
            resultSet.getString("id"),
            resultSet.getString("subscription_id"),
            resultSet.getString("user_id"),
            resultSet.getString("playlist_name"),
            resultSet.getInt("matched_count"),
            resultSet.getInt("queued_count"),
            resultSet.getString("state"),
            resultSet.getString("error"),
            resultSet.getLong("created_at"),
            completedAt == null ? null : resultSet.getLong("completed_at")
        );
    }

    record Run(
        String id, String subscriptionId, String userId, String playlistName,
        int matchedCount, int queuedCount, String state, String error,
        long createdAt, Long completedAt
    ) {
    }

    record RunTask(
        String taskId, String title, String artist, String state, String message
    ) {
        boolean terminal() {
            return state == null || "COMPLETED".equals(state) || "FAILED".equals(state);
        }

        boolean failed() {
            return state == null || "FAILED".equals(state);
        }
    }
}
