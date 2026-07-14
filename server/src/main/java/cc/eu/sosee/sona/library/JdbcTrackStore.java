package cc.eu.sosee.sona.library;

import java.nio.file.Path;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class JdbcTrackStore implements TrackStore {

    private static final RowMapper<TrackRecord> ROW_MAPPER = JdbcTrackStore::mapTrack;

    private final JdbcClient jdbcClient;
    private final CursorCodec cursorCodec;

    JdbcTrackStore(JdbcClient jdbcClient) {
        this.jdbcClient = jdbcClient;
        this.cursorCodec = new CursorCodec();
    }

    @Override
    public Optional<TrackRecord> findByPath(Path path) {
        return jdbcClient.sql("SELECT * FROM tracks WHERE path = :path")
            .param("path", path.toAbsolutePath().normalize().toString())
            .query(ROW_MAPPER)
            .optional();
    }

    @Override
    public Optional<TrackRecord> findById(String id) {
        return jdbcClient.sql("SELECT * FROM tracks WHERE id = :id")
            .param("id", id)
            .query(ROW_MAPPER)
            .optional();
    }

    @Override
    public void save(TrackRecord track) {
        jdbcClient.sql("""
                INSERT INTO tracks(
                    id, path, file_size, modified_at, title, normalized_title, artist, album,
                    track_number, duration_ms, codec, sample_rate, bit_depth, artwork_path,
                    plain_lyrics, synced_lyrics, lyrics_source, metadata_status, manual_edited,
                    created_at, updated_at
                ) VALUES (
                    :id, :path, :fileSize, :modifiedAt, :title, :normalizedTitle, :artist, :album,
                    :trackNumber, :durationMs, :codec, :sampleRate, :bitDepth, :artworkPath,
                    :plainLyrics, :syncedLyrics, :lyricsSource, :metadataStatus, :manualEdited,
                    :createdAt, :updatedAt
                )
                ON CONFLICT(path) DO UPDATE SET
                    file_size = excluded.file_size,
                    modified_at = excluded.modified_at,
                    title = CASE WHEN tracks.manual_edited = 1 THEN tracks.title ELSE excluded.title END,
                    normalized_title = CASE WHEN tracks.manual_edited = 1 THEN tracks.normalized_title ELSE excluded.normalized_title END,
                    artist = CASE WHEN tracks.manual_edited = 1 THEN tracks.artist ELSE excluded.artist END,
                    album = CASE WHEN tracks.manual_edited = 1 THEN tracks.album ELSE excluded.album END,
                    track_number = CASE WHEN tracks.manual_edited = 1 THEN tracks.track_number ELSE excluded.track_number END,
                    duration_ms = excluded.duration_ms,
                    codec = excluded.codec,
                    sample_rate = excluded.sample_rate,
                    bit_depth = excluded.bit_depth,
                    artwork_path = COALESCE(tracks.artwork_path, excluded.artwork_path),
                    plain_lyrics = COALESCE(tracks.plain_lyrics, excluded.plain_lyrics),
                    synced_lyrics = COALESCE(tracks.synced_lyrics, excluded.synced_lyrics),
                    lyrics_source = COALESCE(tracks.lyrics_source, excluded.lyrics_source),
                    metadata_status = CASE WHEN tracks.manual_edited = 1 THEN tracks.metadata_status ELSE excluded.metadata_status END,
                    updated_at = excluded.updated_at
                """)
            .param("id", track.id())
            .param("path", track.path().toAbsolutePath().normalize().toString())
            .param("fileSize", track.fileSize())
            .param("modifiedAt", track.modifiedAt())
            .param("title", track.title())
            .param("normalizedTitle", track.normalizedTitle())
            .param("artist", track.artist())
            .param("album", track.album())
            .param("trackNumber", track.trackNumber())
            .param("durationMs", track.durationMs())
            .param("codec", track.codec())
            .param("sampleRate", track.sampleRate())
            .param("bitDepth", track.bitDepth())
            .param("artworkPath", string(track.artworkPath()))
            .param("plainLyrics", track.plainLyrics())
            .param("syncedLyrics", track.syncedLyrics())
            .param("lyricsSource", track.lyricsSource())
            .param("metadataStatus", track.metadataStatus())
            .param("manualEdited", track.manualEdited() ? 1 : 0)
            .param("createdAt", track.createdAt())
            .param("updatedAt", track.updatedAt())
            .update();
    }

    @Override
    public TrackPageData findPage(String query, String cursor, int limit) {
        var normalizedQuery = query == null ? "" : query.strip();
        var decodedCursor = cursor == null || cursor.isBlank() ? null : cursorCodec.decode(cursor);

        var sql = new StringBuilder("SELECT * FROM tracks WHERE 1 = 1");
        if (!normalizedQuery.isBlank()) {
            sql.append(" AND (title LIKE :query OR artist LIKE :query OR album LIKE :query)");
        }
        if (decodedCursor != null) {
            sql.append(" AND (normalized_title > :cursorTitle OR (normalized_title = :cursorTitle AND id > :cursorId))");
        }
        sql.append(" ORDER BY normalized_title, id LIMIT :limit");

        var statement = jdbcClient.sql(sql.toString()).param("limit", limit + 1);
        if (!normalizedQuery.isBlank()) {
            statement = statement.param("query", "%" + normalizedQuery + "%");
        }
        if (decodedCursor != null) {
            statement = statement
                .param("cursorTitle", decodedCursor.normalizedTitle())
                .param("cursorId", decodedCursor.id());
        }

        var results = new ArrayList<>(statement.query(ROW_MAPPER).list());
        String nextCursor = null;
        if (results.size() > limit) {
            results.remove(results.size() - 1);
            var last = results.get(results.size() - 1);
            nextCursor = cursorCodec.encode(new TrackCursor(last.normalizedTitle(), last.id()));
        }
        return new TrackPageData(results, nextCursor);
    }

    @Override
    public List<TrackRecord> findRandom(int limit) {
        return jdbcClient.sql("""
                SELECT tracks.*
                FROM tracks
                LEFT JOIN track_play_stats stats ON stats.track_id = tracks.id
                ORDER BY ABS(RANDOM() % 1000000) * (
                    1.0 + 4.0 * CASE
                        WHEN COALESCE(stats.play_count, 0) > 0
                        THEN MIN(stats.completion_count, stats.play_count) * 1.0 / stats.play_count
                        ELSE 0
                    END
                ) DESC
                LIMIT :limit
                """)
            .param("limit", limit)
            .query(ROW_MAPPER)
            .list();
    }

    private static TrackRecord mapTrack(ResultSet resultSet, int rowNumber) throws SQLException {
        return new TrackRecord(
            resultSet.getString("id"),
            Path.of(resultSet.getString("path")),
            resultSet.getLong("file_size"),
            resultSet.getLong("modified_at"),
            resultSet.getString("title"),
            resultSet.getString("normalized_title"),
            resultSet.getString("artist"),
            resultSet.getString("album"),
            integer(resultSet, "track_number"),
            resultSet.getLong("duration_ms"),
            resultSet.getString("codec"),
            integer(resultSet, "sample_rate"),
            integer(resultSet, "bit_depth"),
            path(resultSet.getString("artwork_path")),
            resultSet.getString("plain_lyrics"),
            resultSet.getString("synced_lyrics"),
            resultSet.getString("lyrics_source"),
            resultSet.getString("metadata_status"),
            resultSet.getInt("manual_edited") == 1,
            resultSet.getLong("created_at"),
            resultSet.getLong("updated_at")
        );
    }

    private static Integer integer(ResultSet resultSet, String column) throws SQLException {
        var value = resultSet.getInt(column);
        return resultSet.wasNull() ? null : value;
    }

    private static Path path(String value) {
        return value == null ? null : Path.of(value);
    }

    private static String string(Path path) {
        return path == null ? null : path.toString();
    }
}
