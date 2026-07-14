package cc.eu.sosee.sona.auth;

import java.time.Clock;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class SessionRepository {

    private final JdbcClient jdbcClient;
    private final Clock clock;

    SessionRepository(JdbcClient jdbcClient, Clock clock) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
    }

    void create(String tokenHash, String userId, long expiresAt) {
        jdbcClient.sql("""
                INSERT INTO sessions(token_hash, user_id, expires_at, created_at)
                VALUES (:tokenHash, :userId, :expiresAt, :createdAt)
                """)
            .param("tokenHash", tokenHash)
            .param("userId", userId)
            .param("expiresAt", expiresAt)
            .param("createdAt", clock.millis())
            .update();
    }

    Optional<AuthenticatedUser> findActiveUser(String tokenHash) {
        return jdbcClient.sql("""
                SELECT users.id, users.username, users.role
                FROM sessions
                JOIN users ON users.id = sessions.user_id
                WHERE sessions.token_hash = :tokenHash
                  AND sessions.expires_at > :now
                  AND users.enabled = 1
                """)
            .param("tokenHash", tokenHash)
            .param("now", clock.millis())
            .query((resultSet, rowNumber) -> new AuthenticatedUser(
                resultSet.getString("id"),
                resultSet.getString("username"),
                UserRole.valueOf(resultSet.getString("role"))
            ))
            .optional();
    }

    void delete(String tokenHash) {
        jdbcClient.sql("DELETE FROM sessions WHERE token_hash = :tokenHash")
            .param("tokenHash", tokenHash)
            .update();
    }

    void deleteExpired() {
        jdbcClient.sql("DELETE FROM sessions WHERE expires_at <= :now")
            .param("now", clock.millis())
            .update();
    }

    void deleteForUser(String userId) {
        jdbcClient.sql("DELETE FROM sessions WHERE user_id = :userId")
            .param("userId", userId)
            .update();
    }
}
