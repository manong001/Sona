package cc.eu.sosee.sona.auth;

import java.time.Clock;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
class UserRepository {

    private final JdbcClient jdbcClient;
    private final Clock clock;

    UserRepository(JdbcClient jdbcClient, Clock clock) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
    }

    Optional<UserAccount> findByUsername(String username) {
        return jdbcClient.sql("""
                SELECT id, username, password_hash, role, enabled
                FROM users
                WHERE username = :username COLLATE NOCASE
                """)
            .param("username", username)
            .query(this::mapAccount)
            .optional();
    }

    Optional<UserAccount> findById(String id) {
        return jdbcClient.sql("""
                SELECT id, username, password_hash, role, enabled
                FROM users
                WHERE id = :id
                """)
            .param("id", id)
            .query(this::mapAccount)
            .optional();
    }

    List<UserAccount> findAll() {
        return jdbcClient.sql("""
                SELECT id, username, password_hash, role, enabled
                FROM users
                ORDER BY CASE role WHEN 'ADMIN' THEN 0 ELSE 1 END, username COLLATE NOCASE
                """)
            .query(this::mapAccount)
            .list();
    }

    UserAccount create(String username, String passwordHash, UserRole role) {
        var account = new UserAccount(UUID.randomUUID().toString(), username, passwordHash, role, true);
        jdbcClient.sql("""
                INSERT INTO users(id, username, password_hash, role, enabled, created_at)
                VALUES (:id, :username, :passwordHash, :role, 1, :createdAt)
                """)
            .param("id", account.id())
            .param("username", account.username())
            .param("passwordHash", account.passwordHash())
            .param("role", role.name())
            .param("createdAt", clock.millis())
            .update();
        return account;
    }

    void makeAdmin(String id) {
        jdbcClient.sql("UPDATE users SET role = 'ADMIN', enabled = 1 WHERE id = :id")
            .param("id", id)
            .update();
    }

    boolean setEnabled(String id, boolean enabled) {
        return jdbcClient.sql("UPDATE users SET enabled = :enabled WHERE id = :id")
            .param("enabled", enabled ? 1 : 0)
            .param("id", id)
            .update() == 1;
    }

    boolean updatePassword(String id, String passwordHash) {
        return jdbcClient.sql("UPDATE users SET password_hash = :passwordHash WHERE id = :id")
            .param("passwordHash", passwordHash)
            .param("id", id)
            .update() == 1;
    }

    @Transactional
    boolean delete(String id) {
        jdbcClient.sql("DELETE FROM playback_state WHERE user_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM hidden_tracks WHERE user_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM playback_records WHERE user_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM play_history WHERE user_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM favorites WHERE user_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM playlists WHERE user_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM sessions WHERE user_id = :id").param("id", id).update();
        return jdbcClient.sql("DELETE FROM users WHERE id = :id")
            .param("id", id)
            .update() == 1;
    }

    private UserAccount mapAccount(java.sql.ResultSet resultSet, int rowNumber)
        throws java.sql.SQLException {
        return new UserAccount(
            resultSet.getString("id"),
            resultSet.getString("username"),
            resultSet.getString("password_hash"),
            UserRole.valueOf(resultSet.getString("role")),
            resultSet.getBoolean("enabled")
        );
    }
}
