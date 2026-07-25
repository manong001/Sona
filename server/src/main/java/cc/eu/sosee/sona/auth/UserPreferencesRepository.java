package cc.eu.sosee.sona.auth;

import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

@Repository
class UserPreferencesRepository {

    private final JdbcClient jdbcClient;
    private final ObjectMapper objectMapper;

    UserPreferencesRepository(JdbcClient jdbcClient, ObjectMapper objectMapper) {
        this.jdbcClient = jdbcClient;
        this.objectMapper = objectMapper;
    }

    Optional<StoredUserPreferences> find(String userId) {
        return jdbcClient.sql("""
                SELECT preferences_json, updated_at
                FROM user_preferences WHERE user_id = :userId
                """)
            .param("userId", userId)
            .query((resultSet, rowNumber) -> new StoredUserPreferences(
                read(resultSet.getString("preferences_json")),
                resultSet.getLong("updated_at")
            ))
            .optional();
    }

    StoredUserPreferences save(String userId, UserPreferencesValue value) {
        var updatedAt = System.currentTimeMillis();
        jdbcClient.sql("""
                INSERT INTO user_preferences(user_id, preferences_json, updated_at)
                VALUES (:userId, :preferencesJson, :updatedAt)
                ON CONFLICT(user_id) DO UPDATE SET
                    preferences_json = excluded.preferences_json,
                    updated_at = excluded.updated_at
                """)
            .param("userId", userId)
            .param("preferencesJson", write(value))
            .param("updatedAt", updatedAt)
            .update();
        return new StoredUserPreferences(value, updatedAt);
    }

    private UserPreferencesValue read(String json) {
        try {
            return objectMapper.readValue(json, UserPreferencesValue.class);
        } catch (JacksonException exception) {
            throw new IllegalStateException("Stored user preferences are invalid", exception);
        }
    }

    private String write(UserPreferencesValue value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JacksonException exception) {
            throw new IllegalStateException("Could not store user preferences", exception);
        }
    }

    record StoredUserPreferences(UserPreferencesValue value, long updatedAt) {
    }
}
