package cc.eu.sosee.sona.auth;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Clock;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class SystemNotificationRepository {

    private final JdbcClient jdbcClient;
    private final Clock clock;

    SystemNotificationRepository(JdbcClient jdbcClient, Clock clock) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
    }

    SystemNotification create(String userId, String type, String title, String body) {
        var notification = new SystemNotification(
            UUID.randomUUID().toString(), type, title, body, null, clock.millis()
        );
        jdbcClient.sql("""
                INSERT INTO system_notifications (
                    id, user_id, type, title, body, read_at, created_at
                ) VALUES (:id, :userId, :type, :title, :body, NULL, :createdAt)
                """)
            .param("id", notification.id())
            .param("userId", userId)
            .param("type", type)
            .param("title", title)
            .param("body", body)
            .param("createdAt", notification.createdAt())
            .update();
        return notification;
    }

    List<SystemNotification> findRecent(String userId) {
        return jdbcClient.sql("""
                SELECT id, type, title, body, read_at, created_at
                FROM system_notifications
                WHERE user_id = :userId
                ORDER BY created_at DESC
                LIMIT 100
                """)
            .param("userId", userId)
            .query(this::map)
            .list();
    }

    boolean markRead(String userId, String id) {
        return jdbcClient.sql("""
                UPDATE system_notifications
                SET read_at = COALESCE(read_at, :readAt)
                WHERE id = :id AND user_id = :userId
                """)
            .param("readAt", clock.millis())
            .param("id", id)
            .param("userId", userId)
            .update() == 1;
    }

    void markAllRead(String userId) {
        jdbcClient.sql("""
                UPDATE system_notifications SET read_at = :readAt
                WHERE user_id = :userId AND read_at IS NULL
                """)
            .param("readAt", clock.millis())
            .param("userId", userId)
            .update();
    }

    private SystemNotification map(ResultSet resultSet, int rowNumber) throws SQLException {
        var readAt = resultSet.getObject("read_at");
        return new SystemNotification(
            resultSet.getString("id"),
            resultSet.getString("type"),
            resultSet.getString("title"),
            resultSet.getString("body"),
            readAt == null ? null : resultSet.getLong("read_at"),
            resultSet.getLong("created_at")
        );
    }

    record SystemNotification(
        String id, String type, String title, String body, Long readAt, long createdAt
    ) {
    }
}
