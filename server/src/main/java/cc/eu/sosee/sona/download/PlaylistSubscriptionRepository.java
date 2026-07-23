package cc.eu.sosee.sona.download;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Clock;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
class PlaylistSubscriptionRepository {

    private final JdbcClient jdbcClient;
    private final Clock clock;

    PlaylistSubscriptionRepository(JdbcClient jdbcClient, Clock clock) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
    }

    Subscription create(
        String userId, String playlistId, String sourceUrl, String name,
        String poolType, boolean autoDownload, int syncIntervalHours
    ) {
        var now = clock.millis();
        var id = UUID.randomUUID().toString();
        jdbcClient.sql("""
                INSERT INTO playlist_subscriptions (
                    id, user_id, playlist_id, source_url, name, pool_type, auto_download,
                    sync_interval_hours, enabled, created_at, updated_at
                ) VALUES (
                    :id, :userId, :playlistId, :sourceUrl, :name, :poolType, :autoDownload,
                    :syncIntervalHours, 1, :now, :now
                )
                """)
            .param("id", id)
            .param("userId", userId)
            .param("playlistId", playlistId)
            .param("sourceUrl", sourceUrl)
            .param("name", name)
            .param("poolType", poolType)
            .param("autoDownload", autoDownload ? 1 : 0)
            .param("syncIntervalHours", syncIntervalHours)
            .param("now", now)
            .update();
        return find(userId, id).orElseThrow();
    }

    List<Subscription> findAll(String userId) {
        return select("WHERE subscriptions.user_id = :userId ORDER BY subscriptions.created_at DESC")
            .param("userId", userId)
            .query(this::map)
            .list();
    }

    Optional<Subscription> find(String userId, String id) {
        return select("WHERE subscriptions.user_id = :userId AND subscriptions.id = :id")
            .param("userId", userId)
            .param("id", id)
            .query(this::map)
            .optional();
    }

    List<String> matchedTrackIds(String subscriptionId) {
        return jdbcClient.sql("""
                WITH resolved_items AS (
                    SELECT items.position, (
                        SELECT tracks.id FROM tracks WHERE tracks.id = items.matched_track_id
                        UNION ALL
                        SELECT tracks.id FROM tracks
                        WHERE items.matched_track_id IS NULL
                          AND trim(tracks.title) COLLATE NOCASE = trim(items.title) COLLATE NOCASE
                          AND replace(trim(tracks.artist), '、', '/') COLLATE NOCASE =
                              replace(trim(items.artist), '、', '/') COLLATE NOCASE
                        ORDER BY id
                        LIMIT 1
                    ) AS track_id
                    FROM playlist_subscription_items items
                    WHERE items.subscription_id = :subscriptionId
                )
                SELECT track_id FROM resolved_items
                WHERE track_id IS NOT NULL
                ORDER BY position
                """)
            .param("subscriptionId", subscriptionId)
            .query(String.class)
            .list();
    }

    List<Item> findItems(String subscriptionId) {
        return jdbcClient.sql("""
                SELECT items.item_key, items.position, items.title, items.artist, items.album,
                    items.matched_track_id, items.last_seen_at,
                    CASE
                        WHEN EXISTS (SELECT 1 FROM tracks WHERE id = items.matched_track_id)
                            THEN 'MATCHED'
                        WHEN EXISTS (
                            SELECT 1 FROM tracks
                            WHERE trim(tracks.title) COLLATE NOCASE = trim(items.title) COLLATE NOCASE
                              AND replace(trim(tracks.artist), '、', '/') COLLATE NOCASE =
                                  replace(trim(items.artist), '、', '/') COLLATE NOCASE
                        ) THEN 'MATCHED'
                        WHEN EXISTS (
                            SELECT 1 FROM download_tasks
                            WHERE trim(download_tasks.title) COLLATE NOCASE = trim(items.title) COLLATE NOCASE
                              AND replace(trim(download_tasks.artist), '、', '/') COLLATE NOCASE =
                                  replace(trim(items.artist), '、', '/') COLLATE NOCASE
                              AND download_tasks.state IN ('QUEUED', 'RUNNING')
                        ) THEN 'DOWNLOADING'
                        WHEN items.state = 'SUGGESTED' THEN 'SUGGESTED'
                        ELSE 'MISSING'
                    END AS state
                FROM playlist_subscription_items items
                WHERE items.subscription_id = :subscriptionId
                ORDER BY items.position
                """)
            .param("subscriptionId", subscriptionId)
            .query(this::mapItem)
            .list();
    }

    Optional<Item> findItem(String userId, String subscriptionId, String itemKey) {
        return jdbcClient.sql("""
                SELECT items.* FROM playlist_subscription_items items
                JOIN playlist_subscriptions subscriptions ON subscriptions.id = items.subscription_id
                WHERE subscriptions.user_id = :userId
                  AND items.subscription_id = :subscriptionId
                  AND items.item_key = :itemKey
                """)
            .param("userId", userId)
            .param("subscriptionId", subscriptionId)
            .param("itemKey", itemKey)
            .query(this::mapItem)
            .optional();
    }

    boolean selectMatch(String userId, String subscriptionId, String itemKey, String trackId) {
        return jdbcClient.sql("""
                UPDATE playlist_subscription_items
                SET matched_track_id = :trackId, state = 'MATCHED'
                WHERE subscription_id = :subscriptionId AND item_key = :itemKey
                  AND EXISTS (SELECT 1 FROM playlist_subscriptions
                      WHERE id = :subscriptionId AND user_id = :userId)
                  AND EXISTS (SELECT 1 FROM tracks WHERE id = :trackId)
                  AND NOT EXISTS (
                      SELECT 1 FROM playlist_subscription_items other
                      WHERE other.subscription_id = :subscriptionId
                        AND other.item_key <> :itemKey
                        AND other.matched_track_id = :trackId
                  )
                """)
            .param("trackId", trackId)
            .param("subscriptionId", subscriptionId)
            .param("itemKey", itemKey)
            .param("userId", userId)
            .update() == 1;
    }

    boolean bindDownloadedTrack(
        String playlistId, String title, String artist, String trackId
    ) {
        return jdbcClient.sql("""
                UPDATE playlist_subscription_items
                SET matched_track_id = :trackId, state = 'MATCHED'
                WHERE rowid = (
                    SELECT items.rowid
                    FROM playlist_subscription_items items
                    JOIN playlist_subscriptions subscriptions
                      ON subscriptions.id = items.subscription_id
                    WHERE subscriptions.playlist_id = :playlistId
                      AND items.matched_track_id IS NULL
                      AND trim(items.title) COLLATE NOCASE = trim(:title) COLLATE NOCASE
                      AND replace(trim(items.artist), '、', '/') COLLATE NOCASE =
                          replace(trim(:artist), '、', '/') COLLATE NOCASE
                      AND EXISTS (
                          SELECT 1 FROM playlist_tracks
                          WHERE playlist_id = :playlistId AND track_id = :trackId
                      )
                      AND NOT EXISTS (
                          SELECT 1 FROM playlist_subscription_items other
                          WHERE other.subscription_id = items.subscription_id
                            AND other.matched_track_id = :trackId
                      )
                    ORDER BY items.position
                    LIMIT 1
                )
                """)
            .param("playlistId", playlistId)
            .param("title", title.strip())
            .param("artist", artist.strip())
            .param("trackId", trackId)
            .update() == 1;
    }

    void updateItemState(String subscriptionId, String itemKey, String state) {
        jdbcClient.sql("""
                UPDATE playlist_subscription_items SET state = :state
                WHERE subscription_id = :subscriptionId AND item_key = :itemKey
                """)
            .param("state", state)
            .param("subscriptionId", subscriptionId)
            .param("itemKey", itemKey)
            .update();
    }

    List<Subscription> findDue() {
        var now = clock.millis();
        return select("""
                WHERE subscriptions.enabled = 1
                  AND (subscriptions.last_synced_at IS NULL
                    OR subscriptions.last_synced_at + subscriptions.sync_interval_hours * 3600000 <= :now)
                ORDER BY COALESCE(subscriptions.last_synced_at, 0), subscriptions.created_at
                """)
            .param("now", now)
            .query(this::map)
            .list();
    }

    @Transactional
    void replaceItems(String subscriptionId, List<Item> items) {
        jdbcClient.sql("DELETE FROM playlist_subscription_items WHERE subscription_id = :id")
            .param("id", subscriptionId)
            .update();
        for (var item : items) {
            jdbcClient.sql("""
                    INSERT INTO playlist_subscription_items (
                        subscription_id, item_key, position, title, artist, album,
                        matched_track_id, state, last_seen_at
                    ) VALUES (
                        :subscriptionId, :itemKey, :position, :title, :artist, :album,
                        :matchedTrackId, :state, :lastSeenAt
                    )
                    """)
                .param("subscriptionId", subscriptionId)
                .param("itemKey", item.itemKey())
                .param("position", item.position())
                .param("title", item.title())
                .param("artist", item.artist())
                .param("album", item.album())
                .param("matchedTrackId", item.matchedTrackId())
                .param("state", item.state())
                .param("lastSeenAt", item.lastSeenAt())
                .update();
        }
    }

    void markSynced(String id) {
        var now = clock.millis();
        jdbcClient.sql("""
                UPDATE playlist_subscriptions
                SET last_synced_at = :now, last_error = NULL, updated_at = :now
                WHERE id = :id
                """)
            .param("now", now)
            .param("id", id)
            .update();
    }

    void rename(String id, String name) {
        jdbcClient.sql("""
                UPDATE playlist_subscriptions SET name = :name, updated_at = :now WHERE id = :id
                """)
            .param("name", name)
            .param("now", clock.millis())
            .param("id", id)
            .update();
    }

    void updateArtwork(String id, String artworkUrl) {
        jdbcClient.sql("""
                UPDATE playlist_subscriptions
                SET artwork_url = :artworkUrl, updated_at = :now
                WHERE id = :id
                """)
            .param("artworkUrl", artworkUrl)
            .param("now", clock.millis())
            .param("id", id)
            .update();
    }

    void markFailed(String id, String message) {
        jdbcClient.sql("""
                UPDATE playlist_subscriptions SET last_error = :message, updated_at = :now
                WHERE id = :id
                """)
            .param("message", message)
            .param("now", clock.millis())
            .param("id", id)
            .update();
    }

    @Transactional
    boolean delete(String userId, String id) {
        var deleted = jdbcClient.sql("""
                DELETE FROM playlist_subscriptions WHERE id = :id AND user_id = :userId
                """)
            .param("id", id)
            .param("userId", userId)
            .update() == 1;
        if (deleted) {
            jdbcClient.sql("DELETE FROM playlist_subscription_items WHERE subscription_id = :id")
                .param("id", id)
                .update();
        }
        return deleted;
    }

    private JdbcClient.StatementSpec select(String suffix) {
        return jdbcClient.sql("""
            WITH item_states AS (
                SELECT items.subscription_id,
                    CASE
                        WHEN EXISTS (
                            SELECT 1 FROM tracks WHERE tracks.id = items.matched_track_id
                        ) THEN 'MATCHED'
                        WHEN EXISTS (
                            SELECT 1 FROM tracks
                            WHERE trim(tracks.title) COLLATE NOCASE =
                                  trim(items.title) COLLATE NOCASE
                              AND replace(trim(tracks.artist), '、', '/') COLLATE NOCASE =
                                  replace(trim(items.artist), '、', '/') COLLATE NOCASE
                        ) THEN 'MATCHED'
                        WHEN EXISTS (
                            SELECT 1 FROM download_tasks tasks
                            WHERE trim(tasks.title) COLLATE NOCASE =
                                  trim(items.title) COLLATE NOCASE
                              AND replace(trim(tasks.artist), '、', '/') COLLATE NOCASE =
                                  replace(trim(items.artist), '、', '/') COLLATE NOCASE
                              AND tasks.state = 'RUNNING'
                        ) THEN 'RUNNING'
                        WHEN EXISTS (
                            SELECT 1 FROM download_tasks tasks
                            WHERE trim(tasks.title) COLLATE NOCASE =
                                  trim(items.title) COLLATE NOCASE
                              AND replace(trim(tasks.artist), '、', '/') COLLATE NOCASE =
                                  replace(trim(items.artist), '、', '/') COLLATE NOCASE
                              AND tasks.state = 'QUEUED'
                        ) THEN 'QUEUED'
                        WHEN items.state = 'SUGGESTED' THEN 'SUGGESTED'
                        ELSE 'MISSING'
                    END AS state
                FROM playlist_subscription_items items
            )
            SELECT subscriptions.*, users.username,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id) AS item_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id AND items.state = 'MATCHED') AS matched_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id AND items.state = 'MISSING') AS missing_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id AND items.state = 'SUGGESTED') AS suggested_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id
                      AND items.state IN ('QUEUED', 'RUNNING')) AS downloading_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id AND items.state = 'QUEUED') AS queued_count,
                (SELECT COUNT(*) FROM item_states items
                    WHERE items.subscription_id = subscriptions.id AND items.state = 'RUNNING') AS running_count
            FROM playlist_subscriptions subscriptions
            JOIN users ON users.id = subscriptions.user_id
            """ + suffix);
    }

    private Subscription map(ResultSet resultSet, int rowNumber) throws SQLException {
        var lastSyncedAt = resultSet.getLong("last_synced_at");
        Long nullableLastSyncedAt = resultSet.wasNull() ? null : lastSyncedAt;
        return new Subscription(
            resultSet.getString("id"), resultSet.getString("user_id"),
            resultSet.getString("username"), resultSet.getString("playlist_id"),
            resultSet.getString("source_url"), resultSet.getString("name"),
            resultSet.getString("pool_type"), resultSet.getInt("auto_download") == 1,
            resultSet.getInt("sync_interval_hours"), resultSet.getInt("enabled") == 1,
            nullableLastSyncedAt, resultSet.getString("last_error"),
            resultSet.getLong("created_at"), resultSet.getLong("updated_at"),
            resultSet.getInt("item_count"), resultSet.getInt("matched_count"),
            resultSet.getInt("missing_count"), resultSet.getInt("downloading_count"),
            resultSet.getInt("queued_count"), resultSet.getInt("running_count"),
            resultSet.getInt("suggested_count")
        );
    }

    private Item mapItem(ResultSet resultSet, int rowNumber) throws SQLException {
        return new Item(
            resultSet.getString("item_key"), resultSet.getInt("position"),
            resultSet.getString("title"), resultSet.getString("artist"),
            resultSet.getString("album"), resultSet.getString("matched_track_id"),
            resultSet.getString("state"), resultSet.getLong("last_seen_at")
        );
    }

    record Subscription(
        String id, String userId, String username, String playlistId, String sourceUrl,
        String name, String poolType, boolean autoDownload, int syncIntervalHours,
        boolean enabled, Long lastSyncedAt, String lastError, long createdAt, long updatedAt,
        int itemCount, int matchedCount, int missingCount, int downloadingCount,
        int queuedCount, int runningCount, int suggestedCount
    ) {
        Subscription(
            String id, String userId, String username, String playlistId, String sourceUrl,
            String name, String poolType, boolean autoDownload, int syncIntervalHours,
            boolean enabled, Long lastSyncedAt, String lastError, long createdAt, long updatedAt,
            int itemCount, int matchedCount, int missingCount, int downloadingCount
        ) {
            this(
                id, userId, username, playlistId, sourceUrl, name, poolType, autoDownload,
                syncIntervalHours, enabled, lastSyncedAt, lastError, createdAt, updatedAt,
                itemCount, matchedCount, missingCount, downloadingCount, 0, 0, 0
            );
        }
    }

    record Item(
        String itemKey, int position, String title, String artist, String album,
        String matchedTrackId, String state, long lastSeenAt
    ) {
    }
}
