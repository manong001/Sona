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

    Optional<String> findActiveUsername(String tokenHash) {
        return jdbcClient.sql("""
                SELECT users.username
                FROM sessions
                JOIN users ON users.id = sessions.user_id
                WHERE sessions.token_hash = :tokenHash
                  AND sessions.expires_at > :now
                """)
            .param("tokenHash", tokenHash)
            .param("now", clock.millis())
            .query(String.class)
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
}

