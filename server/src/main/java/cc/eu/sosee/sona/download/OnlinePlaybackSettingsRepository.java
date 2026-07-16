package cc.eu.sosee.sona.download;

import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class OnlinePlaybackSettingsRepository {

    private static final List<String> IDS = List.of("ikun");
    private final JdbcClient jdbcClient;

    OnlinePlaybackSettingsRepository(JdbcClient jdbcClient) {
        this.jdbcClient = jdbcClient;
    }

    List<OnlinePlaybackSource> findAll() {
        var enabled = jdbcClient.sql("SELECT source_id FROM online_playback_sources WHERE enabled = 1")
            .query(String.class).list();
        return List.of(new OnlinePlaybackSource("ikun", "Ikun（实验性）", enabled.contains("ikun")));
    }

    void setEnabled(String id, boolean enabled) {
        if (!IDS.contains(id)) {
            throw new IllegalArgumentException("未知在线播放音源");
        }
        jdbcClient.sql("""
                INSERT INTO online_playback_sources(source_id, enabled) VALUES (:id, :enabled)
                ON CONFLICT(source_id) DO UPDATE SET enabled = excluded.enabled
                """)
            .param("id", id).param("enabled", enabled ? 1 : 0).update();
    }
}
