package cc.eu.sosee.sona.config;

import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

@Component
@Order(0)
class SchemaMigration implements ApplicationRunner {

    private final JdbcClient jdbcClient;

    SchemaMigration(JdbcClient jdbcClient) {
        this.jdbcClient = jdbcClient;
    }

    @Override
    public void run(ApplicationArguments arguments) {
        if (tableExists("users")) {
            Set<String> columns = columns("users");
            if (!columns.contains("role")) {
                jdbcClient.sql("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'USER'").update();
            }
            if (!columns.contains("enabled")) {
                jdbcClient.sql("ALTER TABLE users ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1").update();
            }
            if (!columns.contains("avatar")) {
                jdbcClient.sql("ALTER TABLE users ADD COLUMN avatar TEXT").update();
            }
        }
        if (tableExists("tracks")) {
            var trackColumns = columns("tracks");
            if (!trackColumns.contains("pool_type")) {
                jdbcClient.sql("ALTER TABLE tracks ADD COLUMN pool_type TEXT NOT NULL DEFAULT 'PENDING'").update();
                jdbcClient.sql("UPDATE tracks SET pool_type = 'NORMAL'").update();
            }
            if (!trackColumns.contains("audience_type")) {
                jdbcClient.sql("ALTER TABLE tracks ADD COLUMN audience_type TEXT NOT NULL DEFAULT 'GENERAL'").update();
            }
            if (!trackColumns.contains("genre")) {
                jdbcClient.sql("ALTER TABLE tracks ADD COLUMN genre TEXT NOT NULL DEFAULT '未分类'").update();
            }
            if (!trackColumns.contains("region")) {
                jdbcClient.sql("ALTER TABLE tracks ADD COLUMN region TEXT NOT NULL DEFAULT 'OTHER'").update();
            }
        }
        if (tableExists("track_play_stats")) {
            var statColumns = columns("track_play_stats");
            if (!statColumns.contains("completion_percent_sum")) {
                jdbcClient.sql("ALTER TABLE track_play_stats ADD COLUMN completion_percent_sum REAL NOT NULL DEFAULT 0").update();
                jdbcClient.sql("UPDATE track_play_stats SET completion_percent_sum = completion_count * 100.0").update();
            }
        }
        if (tableExists("playback_state") && !columns("playback_state").contains("queue_track_ids")) {
            jdbcClient.sql("ALTER TABLE playback_state ADD COLUMN queue_track_ids TEXT NOT NULL DEFAULT ''").update();
        }
        if (tableExists("download_tasks") && !columns("download_tasks").contains("target_playlist_id")) {
            jdbcClient.sql("ALTER TABLE download_tasks ADD COLUMN target_playlist_id TEXT").update();
        }
        if (tableExists("playlists") && !columns("playlists").contains("featured")) {
            jdbcClient.sql("ALTER TABLE playlists ADD COLUMN featured INTEGER NOT NULL DEFAULT 0").update();
        }
    }

    private boolean tableExists(String table) {
        return jdbcClient.sql("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = :table")
            .param("table", table)
            .query(Integer.class)
            .single() == 1;
    }

    private Set<String> columns(String table) {
        return jdbcClient.sql("PRAGMA table_info(" + table + ")")
            .query((resultSet, rowNumber) -> resultSet.getString("name"))
            .list()
            .stream()
            .collect(Collectors.toSet());
    }
}
