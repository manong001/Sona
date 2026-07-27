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
            jdbcClient.sql("""
                    UPDATE tracks SET pool_type = 'CHILD'
                    WHERE audience_type = 'CHILD' AND pool_type IN ('NORMAL', 'DISCOVERY')
                    """).update();
            jdbcClient.sql("""
                    UPDATE tracks SET audience_type =
                      CASE WHEN pool_type = 'CHILD' THEN 'CHILD' ELSE 'GENERAL' END
                    """).update();
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
            if (trackColumns.contains("artwork_path") && trackColumns.contains("created_at")) {
                jdbcClient.sql("""
                        CREATE INDEX IF NOT EXISTS idx_tracks_missing_artwork
                        ON tracks(artwork_path, created_at)
                        """).update();
            }
            if (trackColumns.contains("duration_ms")) {
                jdbcClient.sql("""
                        CREATE INDEX IF NOT EXISTS idx_tracks_duration
                        ON tracks(duration_ms)
                        """).update();
            }
            if (trackColumns.contains("title") && trackColumns.contains("artist")) {
                jdbcClient.sql("""
                        CREATE INDEX IF NOT EXISTS idx_tracks_subscription_match
                        ON tracks(
                            trim(title) COLLATE NOCASE,
                            replace(trim(artist), '、', '/') COLLATE NOCASE
                        )
                        """).update();
            }
        }
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS artwork_backfill_attempts (
                    track_id TEXT PRIMARY KEY,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    retry_at INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT,
                    updated_at INTEGER NOT NULL,
                    FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE INDEX IF NOT EXISTS idx_artwork_backfill_retry
                ON artwork_backfill_attempts(retry_at)
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS track_audio_features (
                    track_id TEXT PRIMARY KEY,
                    version INTEGER NOT NULL,
                    file_size INTEGER NOT NULL,
                    modified_at INTEGER NOT NULL,
                    vector TEXT NOT NULL,
                    tempo_bpm REAL,
                    energy REAL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
                )
                """).update();
        var audioFeatureColumns = columns("track_audio_features");
        if (!audioFeatureColumns.contains("tempo_bpm")) {
            jdbcClient.sql("ALTER TABLE track_audio_features ADD COLUMN tempo_bpm REAL").update();
        }
        if (!audioFeatureColumns.contains("energy")) {
            jdbcClient.sql("ALTER TABLE track_audio_features ADD COLUMN energy REAL").update();
        }
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS recommendation_settings (
                    user_id TEXT PRIMARY KEY,
                    personalized_enabled INTEGER NOT NULL DEFAULT 1,
                    updated_at INTEGER NOT NULL,
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS recommendation_feedback (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    target_type TEXT NOT NULL,
                    target_value TEXT NOT NULL,
                    display_value TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    UNIQUE (user_id, target_type, target_value),
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE INDEX IF NOT EXISTS idx_recommendation_feedback_user
                ON recommendation_feedback(user_id, created_at DESC)
                """).update();
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
        if (tableExists("download_tasks")) {
            var downloadTaskColumns = columns("download_tasks");
            if (!downloadTaskColumns.contains("target_playlist_id")) {
                jdbcClient.sql("ALTER TABLE download_tasks ADD COLUMN target_playlist_id TEXT").update();
            }
            if (!downloadTaskColumns.contains("strict_match")) {
                jdbcClient.sql(
                    "ALTER TABLE download_tasks ADD COLUMN strict_match INTEGER NOT NULL DEFAULT 0"
                ).update();
            }
            if (downloadTaskColumns.contains("title") && downloadTaskColumns.contains("artist")
                && downloadTaskColumns.contains("state")) {
                jdbcClient.sql("""
                        CREATE INDEX IF NOT EXISTS idx_download_tasks_subscription_match
                        ON download_tasks(
                            trim(title) COLLATE NOCASE,
                            replace(trim(artist), '、', '/') COLLATE NOCASE,
                            state
                        )
                        """).update();
            }
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
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS home_items (
                    user_id TEXT NOT NULL,
                    item_id TEXT NOT NULL,
                    position INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL,
                    PRIMARY KEY (user_id, item_id),
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS playlist_order_items (
                    user_id TEXT NOT NULL,
                    playlist_id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    PRIMARY KEY (user_id, playlist_id),
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE INDEX IF NOT EXISTS idx_playlist_order_items_user_position
                ON playlist_order_items(user_id, position)
                """).update();
        if (tableExists("home_playlists")) {
            if (!columns("home_playlists").contains("position")) {
                jdbcClient.sql(
                    "ALTER TABLE home_playlists ADD COLUMN position INTEGER NOT NULL DEFAULT 0"
                ).update();
            }
            jdbcClient.sql("""
                    INSERT OR IGNORE INTO home_items(user_id, item_id, position, created_at)
                    SELECT user_id, playlist_id, position, created_at FROM home_playlists
                    """).update();
        }
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS playlist_subscriptions (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    playlist_id TEXT NOT NULL UNIQUE,
                    source_url TEXT NOT NULL,
                    name TEXT NOT NULL,
                    artwork_url TEXT,
                    pool_type TEXT NOT NULL DEFAULT 'NORMAL',
                    auto_download INTEGER NOT NULL DEFAULT 0,
                    strict_mode INTEGER NOT NULL DEFAULT 1,
                    sync_interval_hours INTEGER NOT NULL DEFAULT 24,
                    enabled INTEGER NOT NULL DEFAULT 1,
                    last_synced_at INTEGER,
                    last_error TEXT,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    UNIQUE (user_id, source_url),
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
                )
                """).update();
        if (!columns("playlist_subscriptions").contains("artwork_url")) {
            jdbcClient.sql("ALTER TABLE playlist_subscriptions ADD COLUMN artwork_url TEXT").update();
        }
        if (!columns("playlist_subscriptions").contains("pending_artwork_hash")) {
            jdbcClient.sql(
                "ALTER TABLE playlist_subscriptions ADD COLUMN pending_artwork_hash TEXT"
            ).update();
        }
        if (!columns("playlist_subscriptions").contains("strict_mode")) {
            jdbcClient.sql(
                "ALTER TABLE playlist_subscriptions ADD COLUMN strict_mode INTEGER NOT NULL DEFAULT 1"
            ).update();
        }
        var subscriptionColumns = columns("playlist_subscriptions");
        if (!subscriptionColumns.contains("latest_version_id")) {
            jdbcClient.sql(
                "ALTER TABLE playlist_subscriptions ADD COLUMN latest_version_id TEXT"
            ).update();
        }
        if (!subscriptionColumns.contains("selected_version_id")) {
            jdbcClient.sql(
                "ALTER TABLE playlist_subscriptions ADD COLUMN selected_version_id TEXT"
            ).update();
        }
        if (!subscriptionColumns.contains("follow_latest")) {
            jdbcClient.sql(
                "ALTER TABLE playlist_subscriptions ADD COLUMN follow_latest INTEGER NOT NULL DEFAULT 1"
            ).update();
        }
        jdbcClient.sql("""
                CREATE INDEX IF NOT EXISTS idx_playlist_subscriptions_due
                ON playlist_subscriptions(enabled, last_synced_at, updated_at)
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS playlist_subscription_items (
                    subscription_id TEXT NOT NULL,
                    item_key TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    album TEXT,
                    matched_track_id TEXT,
                    state TEXT NOT NULL,
                    last_seen_at INTEGER NOT NULL,
                    PRIMARY KEY (subscription_id, item_key),
                    FOREIGN KEY (subscription_id) REFERENCES playlist_subscriptions(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS playlist_subscription_blacklist (
                    subscription_id TEXT NOT NULL,
                    item_key TEXT NOT NULL,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    PRIMARY KEY (subscription_id, item_key),
                    FOREIGN KEY (subscription_id)
                        REFERENCES playlist_subscriptions(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS playlist_subscription_versions (
                    id TEXT PRIMARY KEY,
                    subscription_id TEXT NOT NULL,
                    version_number INTEGER NOT NULL,
                    name TEXT NOT NULL,
                    artwork_hash TEXT,
                    content_hash TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    UNIQUE (subscription_id, version_number),
                    FOREIGN KEY (subscription_id)
                        REFERENCES playlist_subscriptions(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE INDEX IF NOT EXISTS idx_playlist_subscription_versions
                ON playlist_subscription_versions(subscription_id, version_number DESC)
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS playlist_subscription_version_items (
                    version_id TEXT NOT NULL,
                    item_key TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    album TEXT,
                    matched_track_id TEXT,
                    PRIMARY KEY (version_id, item_key),
                    FOREIGN KEY (version_id)
                        REFERENCES playlist_subscription_versions(id) ON DELETE CASCADE,
                    FOREIGN KEY (matched_track_id) REFERENCES tracks(id) ON DELETE SET NULL
                )
                """).update();
        jdbcClient.sql("""
                CREATE INDEX IF NOT EXISTS idx_playlist_subscription_version_items
                ON playlist_subscription_version_items(version_id, position)
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS playlist_match_choices (
                    user_id TEXT NOT NULL,
                    normalized_title TEXT NOT NULL,
                    normalized_artists TEXT NOT NULL,
                    track_id TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY (user_id, normalized_title, normalized_artists),
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                    FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS system_notifications (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    type TEXT NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    read_at INTEGER,
                    created_at INTEGER NOT NULL,
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE INDEX IF NOT EXISTS idx_system_notifications_user
                ON system_notifications(user_id, read_at, created_at DESC)
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS playlist_automation_runs (
                    id TEXT PRIMARY KEY,
                    subscription_id TEXT NOT NULL,
                    user_id TEXT NOT NULL,
                    playlist_name TEXT NOT NULL,
                    matched_count INTEGER NOT NULL DEFAULT 0,
                    queued_count INTEGER NOT NULL DEFAULT 0,
                    state TEXT NOT NULL,
                    error TEXT,
                    created_at INTEGER NOT NULL,
                    completed_at INTEGER,
                    FOREIGN KEY (subscription_id)
                        REFERENCES playlist_subscriptions(id) ON DELETE CASCADE,
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE INDEX IF NOT EXISTS idx_playlist_automation_runs_due
                ON playlist_automation_runs(subscription_id, created_at DESC)
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS playlist_automation_run_tasks (
                    run_id TEXT NOT NULL,
                    task_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    PRIMARY KEY (run_id, task_id),
                    FOREIGN KEY (run_id)
                        REFERENCES playlist_automation_runs(id) ON DELETE CASCADE
                )
                """).update();
        jdbcClient.sql("""
                CREATE TABLE IF NOT EXISTS track_redownload_tasks (
                    task_id TEXT PRIMARY KEY,
                    source_track_id TEXT NOT NULL,
                    FOREIGN KEY (task_id) REFERENCES download_tasks(id) ON DELETE CASCADE,
                    FOREIGN KEY (source_track_id) REFERENCES tracks(id) ON DELETE CASCADE
                )
                """).update();
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
