package cc.eu.sosee.sona.personal;

import java.nio.file.Path;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Clock;
import java.util.List;
import java.util.Arrays;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
class PersonalRepository {

    private final JdbcClient jdbcClient;
    private final Clock clock;

    PersonalRepository(JdbcClient jdbcClient, Clock clock) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
    }

    List<String> favoriteTrackIds(String userId) {
        return jdbcClient.sql("""
                SELECT track_id
                FROM favorites
                WHERE user_id = :userId
                ORDER BY created_at DESC, track_id
                """)
            .param("userId", userId)
            .query(String.class)
            .list();
    }

    List<ImportRecordData> importRecords(String userId) {
        return jdbcClient.sql("""
                SELECT * FROM import_records
                WHERE user_id = :userId
                ORDER BY created_at DESC
                LIMIT 100
                """)
            .param("userId", userId)
            .query(PersonalRepository::importRecord)
            .list();
    }

    ImportRecordData createImportRecord(
        String userId, String type, String source, String target, int total
    ) {
        var id = UUID.randomUUID().toString();
        var now = clock.millis();
        jdbcClient.sql("""
                INSERT INTO import_records(
                    id, user_id, type, source, target, state, total, created_at, updated_at
                ) VALUES (
                    :id, :userId, :type, :source, :target, 'RUNNING', :total, :createdAt, :updatedAt
                )
                """)
            .param("id", id)
            .param("userId", userId)
            .param("type", type)
            .param("source", source)
            .param("target", target)
            .param("total", total)
            .param("createdAt", now)
            .param("updatedAt", now)
            .update();
        return importRecord(userId, id);
    }

    ImportRecordData updateImportRecord(
        String userId, String id, String state, Integer total, Integer succeeded, Integer failed,
        Integer discovered, Integer imported, Integer updated, Integer skipped, Integer added,
        String message
    ) {
        var changed = jdbcClient.sql("""
                UPDATE import_records
                SET state = :state,
                    total = COALESCE(:total, total),
                    succeeded = COALESCE(:succeeded, succeeded),
                    failed = COALESCE(:failed, failed),
                    discovered = COALESCE(:discovered, discovered),
                    imported = COALESCE(:imported, imported),
                    updated = COALESCE(:updated, updated),
                    skipped = COALESCE(:skipped, skipped),
                    added = COALESCE(:added, added),
                    message = :message,
                    updated_at = :updatedAt
                WHERE id = :id AND user_id = :userId
                """)
            .param("state", state)
            .param("total", total)
            .param("succeeded", succeeded)
            .param("failed", failed)
            .param("discovered", discovered)
            .param("imported", imported)
            .param("updated", updated)
            .param("skipped", skipped)
            .param("added", added)
            .param("message", message)
            .param("updatedAt", clock.millis())
            .param("id", id)
            .param("userId", userId)
            .update();
        if (changed == 0) {
            throw new IllegalArgumentException("Import record not found");
        }
        return importRecord(userId, id);
    }

    private ImportRecordData importRecord(String userId, String id) {
        return jdbcClient.sql("SELECT * FROM import_records WHERE id = :id AND user_id = :userId")
            .param("id", id)
            .param("userId", userId)
            .query(PersonalRepository::importRecord)
            .single();
    }

    private static ImportRecordData importRecord(ResultSet resultSet, int rowNumber) throws SQLException {
        return new ImportRecordData(
            resultSet.getString("id"),
            resultSet.getString("type"),
            resultSet.getString("source"),
            resultSet.getString("target"),
            resultSet.getString("state"),
            resultSet.getInt("total"),
            resultSet.getInt("succeeded"),
            resultSet.getInt("failed"),
            resultSet.getInt("discovered"),
            resultSet.getInt("imported"),
            resultSet.getInt("updated"),
            resultSet.getInt("skipped"),
            resultSet.getInt("added"),
            resultSet.getString("message"),
            resultSet.getLong("created_at"),
            resultSet.getLong("updated_at")
        );
    }

    List<FavoriteTrackData> favoriteTracks(String userId, int offset, int limit) {
        return jdbcClient.sql("""
                SELECT tracks.*
                FROM favorites
                JOIN tracks ON tracks.id = favorites.track_id
                 WHERE favorites.user_id = :userId
                   AND NOT EXISTS (
                     SELECT 1 FROM hidden_tracks
                     WHERE hidden_tracks.user_id = :userId AND hidden_tracks.track_id = tracks.id
                   )
                ORDER BY favorites.created_at DESC, favorites.track_id
                LIMIT :limit OFFSET :offset
                """)
            .param("userId", userId)
            .param("limit", limit)
            .param("offset", offset)
            .query(PersonalRepository::favoriteTrack)
            .list();
    }

    @Transactional
    void addFavorite(String userId, String trackId) {
        insertFavorite(userId, trackId);
        jdbcClient.sql("UPDATE tracks SET pool_type = 'NORMAL' WHERE id = :trackId")
            .param("trackId", trackId)
            .update();
    }

    @Transactional
    int addFavoritesFromDirectory(String userId, Path directory) {
        var trackIds = trackIdsInDirectory(directory);
        var importedCount = 0;
        for (var trackId : trackIds) {
            importedCount += insertFavorite(userId, trackId);
        }
        return importedCount;
    }

    private int insertFavorite(String userId, String trackId) {
        return jdbcClient.sql("""
                INSERT OR IGNORE INTO favorites(user_id, track_id, created_at)
                VALUES (:userId, :trackId, :createdAt)
                """)
            .param("userId", userId)
            .param("trackId", trackId)
            .param("createdAt", clock.millis())
            .update();
    }

    void removeFavorite(String userId, String trackId) {
        jdbcClient.sql("DELETE FROM favorites WHERE user_id = :userId AND track_id = :trackId")
            .param("userId", userId)
            .param("trackId", trackId)
            .update();
    }

    void removeFavorites(String userId, List<String> trackIds) {
        jdbcClient.sql("""
                DELETE FROM favorites
                WHERE user_id = :userId AND track_id IN (:trackIds)
                """)
            .param("userId", userId)
            .param("trackIds", trackIds)
            .update();
    }

    List<PlaylistData> playlists(String userId) {
        return jdbcClient.sql("""
                SELECT id, name, created_at
                FROM playlists
                WHERE user_id = :userId
                ORDER BY created_at
                """)
            .param("userId", userId)
            .query((resultSet, rowNumber) -> new PlaylistData(
                resultSet.getString("id"),
                resultSet.getString("name"),
                trackIds(userId, resultSet.getString("id")),
                resultSet.getLong("created_at")
            ))
            .list();
    }

    PlaylistData createPlaylist(String userId, String name) {
        var id = UUID.randomUUID().toString();
        var createdAt = clock.millis();
        jdbcClient.sql("""
                INSERT INTO playlists(id, user_id, name, created_at)
                VALUES (:id, :userId, :name, :createdAt)
                """)
            .param("id", id)
            .param("userId", userId)
            .param("name", name)
            .param("createdAt", createdAt)
            .update();
        return new PlaylistData(id, name, List.of(), createdAt);
    }

    boolean ownsPlaylist(String userId, String playlistId) {
        return jdbcClient.sql("""
                SELECT COUNT(*)
                FROM playlists
                WHERE id = :playlistId AND user_id = :userId
                """)
            .param("playlistId", playlistId)
            .param("userId", userId)
            .query(Long.class)
            .single() == 1;
    }

    void addPlaylistTrack(String playlistId, String trackId) {
        insertPlaylistTrack(playlistId, trackId);
    }

    @Transactional
    int addPlaylistTracksFromDirectory(String playlistId, Path directory) {
        var importedCount = 0;
        for (var trackId : trackIdsInDirectory(directory)) {
            importedCount += insertPlaylistTrack(playlistId, trackId);
        }
        return importedCount;
    }

    private int insertPlaylistTrack(String playlistId, String trackId) {
        return jdbcClient.sql("""
                INSERT OR IGNORE INTO playlist_tracks(playlist_id, track_id, position, added_at)
                VALUES (
                    :playlistId,
                    :trackId,
                    COALESCE((SELECT MAX(position) + 1 FROM playlist_tracks WHERE playlist_id = :playlistId), 0),
                    :addedAt
                )
                """)
            .param("playlistId", playlistId)
            .param("trackId", trackId)
            .param("addedAt", clock.millis())
            .update();
    }

    private List<String> trackIdsInDirectory(Path directory) {
        var prefix = directory.toAbsolutePath().normalize() + directory.getFileSystem().getSeparator();
        return jdbcClient.sql("""
                SELECT id FROM tracks
                WHERE pool_type <> 'PENDING'
                  AND substr(path, 1, length(:prefix)) = :prefix
                ORDER BY path, id
                """)
            .param("prefix", prefix)
            .query(String.class)
            .list();
    }

    void removePlaylistTrack(String playlistId, String trackId) {
        jdbcClient.sql("""
                DELETE FROM playlist_tracks
                WHERE playlist_id = :playlistId AND track_id = :trackId
                """)
            .param("playlistId", playlistId)
            .param("trackId", trackId)
            .update();
    }

    void removePlaylistTracks(String playlistId, List<String> trackIds) {
        jdbcClient.sql("""
                DELETE FROM playlist_tracks
                WHERE playlist_id = :playlistId AND track_id IN (:trackIds)
                """)
            .param("playlistId", playlistId)
            .param("trackIds", trackIds)
            .update();
    }

    boolean deletePlaylist(String userId, String playlistId) {
        return jdbcClient.sql("""
                DELETE FROM playlists
                WHERE id = :playlistId AND user_id = :userId
                """)
            .param("playlistId", playlistId)
            .param("userId", userId)
            .update() == 1;
    }

    List<HistoryData> history(String userId) {
        return jdbcClient.sql("""
                SELECT track_id, played_at
                FROM play_history
                WHERE user_id = :userId
                ORDER BY played_at DESC
                LIMIT 100
                """)
            .param("userId", userId)
            .query((resultSet, rowNumber) -> new HistoryData(
                resultSet.getString("track_id"),
                resultSet.getLong("played_at")
            ))
            .list();
    }

    @Transactional
    void recordPlayback(String userId, String trackId, long listenedMs, double progressPercent) {
        if (listenedMs < 5_000) {
            return;
        }
        var boundedProgress = Math.max(0, Math.min(progressPercent, 100));
        jdbcClient.sql("""
                INSERT INTO play_history(id, user_id, track_id, played_at)
                VALUES (:id, :userId, :trackId, :playedAt)
                """)
            .param("id", UUID.randomUUID().toString())
            .param("userId", userId)
            .param("trackId", trackId)
            .param("playedAt", clock.millis())
            .update();
        jdbcClient.sql("""
                INSERT INTO playback_records(
                    id, user_id, track_id, listened_ms, progress_percent, played_at
                ) VALUES (:id, :userId, :trackId, :listenedMs, :progressPercent, :playedAt)
                """)
            .param("id", UUID.randomUUID().toString())
            .param("userId", userId)
            .param("trackId", trackId)
            .param("listenedMs", listenedMs)
            .param("progressPercent", boundedProgress)
            .param("playedAt", clock.millis())
            .update();
        jdbcClient.sql("""
                INSERT INTO track_play_stats(
                    track_id, play_count, completion_count, completion_percent_sum
                ) VALUES (:trackId, 1, :completed, :progressPercent)
                ON CONFLICT(track_id) DO UPDATE SET
                    play_count = play_count + 1,
                    completion_count = completion_count + :completed,
                    completion_percent_sum = completion_percent_sum + :progressPercent
                """)
            .param("trackId", trackId)
            .param("completed", boundedProgress >= 95 ? 1 : 0)
            .param("progressPercent", boundedProgress)
            .update();
        jdbcClient.sql("""
                UPDATE tracks
                SET pool_type = 'NORMAL', updated_at = :updatedAt
                WHERE id = :trackId
                  AND pool_type = 'DISCOVERY'
                  AND (
                    SELECT COUNT(*) = 10 AND AVG(progress_percent) > 80
                    FROM (
                      SELECT progress_percent
                      FROM playback_records
                      WHERE track_id = :trackId
                      ORDER BY played_at DESC, rowid DESC
                      LIMIT 10
                    ) recent_playbacks
                  )
                """)
            .param("trackId", trackId)
            .param("updatedAt", clock.millis())
            .update();
        jdbcClient.sql("""
                DELETE FROM play_history
                WHERE user_id = :userId
                  AND id NOT IN (
                      SELECT id FROM play_history
                      WHERE user_id = :userId
                      ORDER BY played_at DESC
                      LIMIT 500
                  )
                """)
            .param("userId", userId)
            .update();
    }

    void hideTrack(String userId, String trackId) {
        jdbcClient.sql("""
                INSERT OR IGNORE INTO hidden_tracks(user_id, track_id, created_at)
                VALUES (:userId, :trackId, :createdAt)
                """)
            .param("userId", userId)
            .param("trackId", trackId)
            .param("createdAt", clock.millis())
            .update();
    }

    PlaybackStateData playbackState(String userId) {
        return jdbcClient.sql("""
                SELECT queue_type, queue_context_id, track_id, queue_track_ids, progress_ms, updated_at
                FROM playback_state WHERE user_id = :userId
                """)
            .param("userId", userId)
            .query((resultSet, rowNumber) -> new PlaybackStateData(
                resultSet.getString("queue_type"),
                resultSet.getString("queue_context_id"),
                resultSet.getString("track_id"),
                splitTrackIds(resultSet.getString("queue_track_ids")),
                resultSet.getLong("progress_ms"),
                resultSet.getLong("updated_at")
            ))
            .optional()
            .orElse(null);
    }

    void savePlaybackState(
        String userId, String queueType, String queueContextId, String trackId,
        List<String> queueTrackIds, long progressMs
    ) {
        jdbcClient.sql("""
                INSERT INTO playback_state(
                    user_id, queue_type, queue_context_id, track_id, queue_track_ids, progress_ms, updated_at
                ) VALUES (:userId, :queueType, :queueContextId, :trackId, :queueTrackIds, :progressMs, :updatedAt)
                ON CONFLICT(user_id) DO UPDATE SET
                    queue_type = excluded.queue_type,
                    queue_context_id = excluded.queue_context_id,
                    track_id = excluded.track_id,
                    queue_track_ids = excluded.queue_track_ids,
                    progress_ms = excluded.progress_ms,
                    updated_at = excluded.updated_at
                """)
            .param("userId", userId)
            .param("queueType", queueType)
            .param("queueContextId", queueContextId)
            .param("trackId", trackId)
            .param("queueTrackIds", String.join(",", queueTrackIds))
            .param("progressMs", Math.max(0, progressMs))
            .param("updatedAt", clock.millis())
            .update();
    }

    void recordPlayedBatch(String userId, String queueType, String queueContextId) {
        jdbcClient.sql("""
                INSERT INTO playback_batches(id, user_id, queue_type, queue_context_id, played_at)
                VALUES (:id, :userId, :queueType, :queueContextId, :playedAt)
                """)
            .param("id", UUID.randomUUID().toString())
            .param("userId", userId)
            .param("queueType", queueType)
            .param("queueContextId", queueContextId)
            .param("playedAt", clock.millis())
            .update();
    }

    private List<String> trackIds(String userId, String playlistId) {
        return jdbcClient.sql("""
                SELECT playlist_tracks.track_id
                FROM playlist_tracks
                WHERE playlist_id = :playlistId
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId
                      AND hidden_tracks.track_id = playlist_tracks.track_id
                  )
                ORDER BY position
                """)
            .param("playlistId", playlistId)
            .param("userId", userId)
            .query(String.class)
            .list();
    }

    private static FavoriteTrackData favoriteTrack(ResultSet resultSet, int rowNumber)
        throws SQLException {
        var id = resultSet.getString("id");
        return new FavoriteTrackData(
            id,
            resultSet.getString("title"),
            resultSet.getString("artist"),
            resultSet.getString("album"),
            integer(resultSet, "track_number"),
            resultSet.getLong("duration_ms"),
            resultSet.getString("codec"),
            extension(resultSet.getString("path")),
            integer(resultSet, "sample_rate"),
            integer(resultSet, "bit_depth"),
            resultSet.getString("artwork_path") == null ? null : "/api/v1/tracks/" + id + "/artwork",
            "/api/v1/tracks/" + id + "/stream",
            resultSet.getString("plain_lyrics") != null || resultSet.getString("synced_lyrics") != null,
            resultSet.getString("metadata_status")
        );
    }

    private static Integer integer(ResultSet resultSet, String column) throws SQLException {
        var value = resultSet.getInt(column);
        return resultSet.wasNull() ? null : value;
    }

    private static String extension(String path) {
        var filename = Path.of(path).getFileName().toString();
        var separator = filename.lastIndexOf('.');
        return separator < 0 ? "" : filename.substring(separator + 1).toLowerCase();
    }

    record PlaylistData(String id, String name, List<String> trackIds, long createdAt) {
    }

    record HistoryData(String trackId, long playedAt) {
    }

    private static List<String> splitTrackIds(String value) {
        return value == null || value.isBlank() ? List.of() : Arrays.asList(value.split(","));
    }

    record PlaybackStateData(
        String queueType, String queueContextId, String trackId, List<String> queueTrackIds,
        long progressMs, long updatedAt
    ) {
    }

    record FavoriteTrackData(
        String id,
        String title,
        String artist,
        String album,
        Integer trackNumber,
        long durationMs,
        String codec,
        String fileExtension,
        Integer sampleRate,
        Integer bitDepth,
        String artworkURL,
        String streamURL,
        boolean hasLyrics,
        String metadataStatus
    ) {
    }

    record ImportRecordData(
        String id,
        String type,
        String source,
        String target,
        String state,
        int total,
        int succeeded,
        int failed,
        int discovered,
        int imported,
        int updated,
        int skipped,
        int added,
        String message,
        long createdAt,
        long updatedAt
    ) {
    }
}
