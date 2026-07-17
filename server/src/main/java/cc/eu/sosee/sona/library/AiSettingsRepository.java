package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.config.SonaProperties;
import java.time.Duration;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class AiSettingsRepository {

    private final JdbcClient jdbcClient;
    private final SonaProperties.Ai defaults;
    private final AiSecretCipher cipher;

    AiSettingsRepository(
        JdbcClient jdbcClient, SonaProperties properties, AiSecretCipher cipher
    ) {
        this.jdbcClient = jdbcClient;
        defaults = properties.getAi();
        this.cipher = cipher;
    }

    AiRuntimeSettings runtime() {
        return stored().map(value -> new AiRuntimeSettings(
            value.enabled(),
            value.baseUrl(),
            value.apiKeyCiphertext().isBlank()
                ? defaults.getApiKey() : cipher.decrypt(value.apiKeyCiphertext()),
            value.model(),
            defaults.getTimeout()
        )).orElseGet(() -> new AiRuntimeSettings(
            defaults.isEnabled(), defaults.getBaseUrl(), defaults.getApiKey(),
            defaults.getModel(), defaults.getTimeout()
        ));
    }

    AiSettingsView view() {
        var value = runtime();
        return new AiSettingsView(
            value.enabled(), value.baseUrl(), value.model(), value.apiKeyConfigured()
        );
    }

    AiSettingsView save(
        boolean enabled, String baseUrl, String model, String apiKey
    ) {
        var existingCiphertext = stored().map(StoredSettings::apiKeyCiphertext).orElse("");
        var ciphertext = apiKey == null || apiKey.isBlank()
            ? existingCiphertext
            : cipher.encrypt(apiKey.strip());
        jdbcClient.sql("""
                INSERT INTO ai_settings(id, enabled, base_url, api_key_ciphertext, model, updated_at)
                VALUES (1, :enabled, :baseUrl, :apiKeyCiphertext, :model, :updatedAt)
                ON CONFLICT(id) DO UPDATE SET
                    enabled = excluded.enabled,
                    base_url = excluded.base_url,
                    api_key_ciphertext = excluded.api_key_ciphertext,
                    model = excluded.model,
                    updated_at = excluded.updated_at
                """)
            .param("enabled", enabled ? 1 : 0)
            .param("baseUrl", baseUrl)
            .param("apiKeyCiphertext", ciphertext)
            .param("model", model)
            .param("updatedAt", System.currentTimeMillis())
            .update();
        return view();
    }

    private Optional<StoredSettings> stored() {
        return jdbcClient.sql("""
                SELECT enabled, base_url, api_key_ciphertext, model
                FROM ai_settings WHERE id = 1
                """)
            .query((resultSet, rowNumber) -> new StoredSettings(
                resultSet.getInt("enabled") == 1,
                resultSet.getString("base_url"),
                resultSet.getString("api_key_ciphertext"),
                resultSet.getString("model")
            ))
            .optional();
    }

    private record StoredSettings(
        boolean enabled, String baseUrl, String apiKeyCiphertext, String model
    ) {
    }
}

record AiRuntimeSettings(
    boolean enabled,
    String baseUrl,
    String apiKey,
    String model,
    Duration timeout
) {
    boolean configured() {
        return enabled && hasText(baseUrl) && hasText(apiKey) && hasText(model);
    }

    boolean apiKeyConfigured() {
        return hasText(apiKey);
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }
}

record AiSettingsView(
    boolean enabled,
    String baseUrl,
    String model,
    boolean apiKeyConfigured
) {
}
