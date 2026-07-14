package cc.eu.sosee.sona.auth;

import java.time.Clock;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

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
                SELECT id, username, password_hash
                FROM users
                WHERE username = :username
                """)
            .param("username", username)
            .query((resultSet, rowNumber) -> new UserAccount(
                resultSet.getString("id"),
                resultSet.getString("username"),
                resultSet.getString("password_hash")
            ))
            .optional();
    }

    UserAccount create(String username, String passwordHash) {
        var account = new UserAccount(UUID.randomUUID().toString(), username, passwordHash);
        jdbcClient.sql("""
                INSERT INTO users(id, username, password_hash, created_at)
                VALUES (:id, :username, :passwordHash, :createdAt)
                """)
            .param("id", account.id())
            .param("username", account.username())
            .param("passwordHash", account.passwordHash())
            .param("createdAt", clock.millis())
            .update();
        return account;
    }
}

