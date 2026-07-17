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
            if (!columns.contains("display_name")) {
                jdbcClient.sql("ALTER TABLE users ADD COLUMN display_name TEXT").update();
            }
            if (!columns.contains("signature")) {
                jdbcClient.sql("ALTER TABLE users ADD COLUMN signature TEXT NOT NULL DEFAULT ''").update();
            }
            if (!columns.contains("last_seen_at")) {
                jdbcClient.sql("ALTER TABLE users ADD COLUMN last_seen_at INTEGER").update();
            }
            if (!columns.contains("last_login_at")) {
                jdbcClient.sql("ALTER TABLE users ADD COLUMN last_login_at INTEGER").update();
            }
        }
        if (tableExists("tracks")) {
            var trackColumns = columns("tracks");
            if (!trackColumns.contains("pool_type")) {
                jdbcClient.sql("ALTER TABLE tracks ADD COLUMN pool_type TEXT NOT NULL DEFAULT 'NORMAL'").update();
            }
            jdbcClient.sql("UPDATE tracks SET pool_type = 'NORMAL' WHERE pool_type = 'PENDING'").update();
            jdbcClient.sql("""
                    CREATE TRIGGER IF NOT EXISTS normalize_pending_track_insert
                    AFTER INSERT ON tracks
                    WHEN NEW.pool_type = 'PENDING'
                    BEGIN
                        UPDATE tracks SET pool_type = 'NORMAL' WHERE id = NEW.id;
                    END
                    """).update();
            jdbcClient.sql("""
                    CREATE TRIGGER IF NOT EXISTS normalize_pending_track_update
                    AFTER UPDATE OF pool_type ON tracks
                    WHEN NEW.pool_type = 'PENDING'
                    BEGIN
                        UPDATE tracks SET pool_type = 'NORMAL' WHERE id = NEW.id;
                    END
                    """).update();
            if (!trackColumns.contains("audience_type")) {
                jdbcClient.sql("ALTER TABLE tracks ADD COLUMN audience_type TEXT NOT NULL DEFAULT 'GENERAL'").update();
            }
            if (!trackColumns.contains("genre")) {
                jdbcClient.sql("ALTER TABLE tracks ADD COLUMN genre TEXT NOT NULL DEFAULT '未分类'").update();
            }
            if (!trackColumns.contains("related_genres")) {
                jdbcClient.sql("ALTER TABLE tracks ADD COLUMN related_genres TEXT NOT NULL DEFAULT ''").update();
            }
            if (!trackColumns.contains("region")) {
                jdbcClient.sql("ALTER TABLE tracks ADD COLUMN region TEXT NOT NULL DEFAULT 'OTHER'").update();
            }
            if (!trackColumns.contains("artwork_source")) {
                jdbcClient.sql("ALTER TABLE tracks ADD COLUMN artwork_source TEXT").update();
                if (trackColumns.contains("artwork_path") && trackColumns.contains("metadata_status")) {
                    jdbcClient.sql("""
                            UPDATE tracks SET artwork_source = 'SCRAPED'
                            WHERE artwork_path IS NOT NULL AND metadata_status = 'SCRAPED'
                            """).update();
                }
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
        if (tableExists("playlists")) {
            var playlistColumns = columns("playlists");
            if (!playlistColumns.contains("featured")) {
                jdbcClient.sql("ALTER TABLE playlists ADD COLUMN featured INTEGER NOT NULL DEFAULT 0").update();
            }
            if (!playlistColumns.contains("directory_path")) {
                jdbcClient.sql("ALTER TABLE playlists ADD COLUMN directory_path TEXT").update();
            }
            if (!playlistColumns.contains("pool_type")) {
                jdbcClient.sql("ALTER TABLE playlists ADD COLUMN pool_type TEXT NOT NULL DEFAULT 'NORMAL'").update();
            }
            if (!playlistColumns.contains("artwork_track_id")) {
                jdbcClient.sql("ALTER TABLE playlists ADD COLUMN artwork_track_id TEXT").update();
            }
            jdbcClient.sql(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_playlists_directory ON playlists(directory_path)"
            ).update();
        }
        if (tableExists("home_playlists") && !columns("home_playlists").contains("position")) {
            jdbcClient.sql(
                "ALTER TABLE home_playlists ADD COLUMN position INTEGER NOT NULL DEFAULT 0"
            ).update();
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
