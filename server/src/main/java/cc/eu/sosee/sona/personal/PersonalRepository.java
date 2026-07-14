package cc.eu.sosee.sona.personal;

import java.time.Clock;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

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
                ORDER BY created_at DESC
                """)
            .param("userId", userId)
            .query(String.class)
            .list();
    }

    void addFavorite(String userId, String trackId) {
        jdbcClient.sql("""
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
                trackIds(resultSet.getString("id")),
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
        jdbcClient.sql("""
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

    void removePlaylistTrack(String playlistId, String trackId) {
        jdbcClient.sql("""
                DELETE FROM playlist_tracks
                WHERE playlist_id = :playlistId AND track_id = :trackId
                """)
            .param("playlistId", playlistId)
            .param("trackId", trackId)
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

    void recordPlayback(String userId, String trackId) {
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

    private List<String> trackIds(String playlistId) {
        return jdbcClient.sql("""
                SELECT track_id
                FROM playlist_tracks
                WHERE playlist_id = :playlistId
                ORDER BY position
                """)
            .param("playlistId", playlistId)
            .query(String.class)
            .list();
    }

    record PlaylistData(String id, String name, List<String> trackIds, long createdAt) {
    }

    record HistoryData(String trackId, long playedAt) {
    }
}
