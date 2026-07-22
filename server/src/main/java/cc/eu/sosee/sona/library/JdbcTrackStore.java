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
import org.springframework.transaction.annotation.Transactional;

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
    public Optional<TrackRecord> findVisibleById(String id, String userId) {
        return jdbcClient.sql("""
                SELECT tracks.* FROM tracks
                WHERE tracks.id = :id AND tracks.pool_type IN ('NORMAL', 'DISCOVERY', 'CHILD')
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId AND hidden_tracks.track_id = tracks.id
                  )
                """)
            .param("id", id)
            .param("userId", userId)
            .query(ROW_MAPPER)
            .optional();
    }

    @Override
    public void save(TrackRecord track) {
        save(track, false);
    }

    @Override
    public void save(TrackRecord track, boolean overwriteMetadata) {
        save(track, overwriteMetadata, false);
    }

    @Override
    public void save(
        TrackRecord track, boolean overwriteMetadata, boolean overwriteManualMetadata
    ) {
        jdbcClient.sql("""
                INSERT INTO tracks(
                    id, path, file_size, modified_at, title, normalized_title, artist, album,
                    track_number, duration_ms, codec, sample_rate, bit_depth, artwork_path, artwork_source,
                    plain_lyrics, synced_lyrics, lyrics_source, metadata_status, manual_edited,
                    created_at, updated_at, pool_type, audience_type, genre, related_genres, region
                ) VALUES (
                    :id, :path, :fileSize, :modifiedAt, :title, :normalizedTitle, :artist, :album,
                    :trackNumber, :durationMs, :codec, :sampleRate, :bitDepth, :artworkPath, :artworkSource,
                    :plainLyrics, :syncedLyrics, :lyricsSource, :metadataStatus, :manualEdited,
                    :createdAt, :updatedAt, :poolType, :audienceType, :genre, :relatedGenres, :region
                )
                ON CONFLICT(path) DO UPDATE SET
                    file_size = excluded.file_size,
                    modified_at = excluded.modified_at,
                    title = CASE WHEN tracks.manual_edited = 1 AND :overwriteManualMetadata = 0
                        THEN tracks.title ELSE excluded.title END,
                    normalized_title = CASE WHEN tracks.manual_edited = 1 AND :overwriteManualMetadata = 0
                        THEN tracks.normalized_title ELSE excluded.normalized_title END,
                    artist = CASE WHEN tracks.manual_edited = 1 AND :overwriteManualMetadata = 0
                        THEN tracks.artist ELSE excluded.artist END,
                    album = CASE WHEN tracks.manual_edited = 1 AND :overwriteManualMetadata = 0
                        THEN tracks.album ELSE excluded.album END,
                    track_number = CASE WHEN tracks.manual_edited = 1 AND :overwriteManualMetadata = 0
                        THEN tracks.track_number ELSE excluded.track_number END,
                    duration_ms = excluded.duration_ms,
                    codec = excluded.codec,
                    sample_rate = excluded.sample_rate,
                    bit_depth = excluded.bit_depth,
                    artwork_path = CASE WHEN :overwriteMetadata = 1
                        AND (tracks.manual_edited = 0 OR :overwriteManualMetadata = 1)
                        THEN COALESCE(excluded.artwork_path, tracks.artwork_path)
                        ELSE COALESCE(tracks.artwork_path, excluded.artwork_path) END,
                    artwork_source = CASE WHEN :overwriteMetadata = 1
                        AND (tracks.manual_edited = 0 OR :overwriteManualMetadata = 1)
                        THEN COALESCE(excluded.artwork_source, tracks.artwork_source)
                        ELSE COALESCE(tracks.artwork_source, excluded.artwork_source) END,
                    plain_lyrics = CASE WHEN :overwriteMetadata = 1
                        AND (tracks.manual_edited = 0 OR :overwriteManualMetadata = 1)
                        THEN COALESCE(excluded.plain_lyrics, tracks.plain_lyrics)
                        ELSE COALESCE(tracks.plain_lyrics, excluded.plain_lyrics) END,
                    synced_lyrics = CASE WHEN :overwriteMetadata = 1
                        AND (tracks.manual_edited = 0 OR :overwriteManualMetadata = 1)
                        THEN COALESCE(excluded.synced_lyrics, tracks.synced_lyrics)
                        ELSE COALESCE(tracks.synced_lyrics, excluded.synced_lyrics) END,
                    lyrics_source = CASE WHEN :overwriteMetadata = 1
                        AND (tracks.manual_edited = 0 OR :overwriteManualMetadata = 1)
                        THEN COALESCE(excluded.lyrics_source, tracks.lyrics_source)
                        ELSE COALESCE(tracks.lyrics_source, excluded.lyrics_source) END,
                    metadata_status = CASE WHEN tracks.manual_edited = 1 AND :overwriteManualMetadata = 0
                        THEN tracks.metadata_status ELSE excluded.metadata_status END,
                    manual_edited = CASE WHEN :overwriteManualMetadata = 1
                        THEN excluded.manual_edited ELSE tracks.manual_edited END,
                    genre = CASE WHEN tracks.manual_edited = 1 AND :overwriteManualMetadata = 0
                        THEN tracks.genre ELSE excluded.genre END,
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
            .param("artworkSource", track.artworkSource())
            .param("overwriteMetadata", overwriteMetadata ? 1 : 0)
            .param("overwriteManualMetadata", overwriteManualMetadata ? 1 : 0)
            .param("plainLyrics", track.plainLyrics())
            .param("syncedLyrics", track.syncedLyrics())
            .param("lyricsSource", track.lyricsSource())
            .param("metadataStatus", track.metadataStatus())
            .param("manualEdited", track.manualEdited() ? 1 : 0)
            .param("createdAt", track.createdAt())
            .param("updatedAt", track.updatedAt())
            .param("poolType", track.poolType())
            .param("audienceType", track.audienceType())
            .param("genre", track.genre())
            .param("relatedGenres", encodeGenres(track.relatedGenres()))
            .param("region", track.region())
            .update();
    }

    @Override
    public TrackPageData findPage(
        String query, String cursor, int limit, String userId, boolean childOnly,
        String sort, String genre, String codec, String metadataStatus
    ) {
        var normalizedQuery = query == null ? "" : query.strip();
        var normalizedSort = sort == null ? "TITLE" : sort.toUpperCase();
        var offset = parseOffset(cursor);

        var sql = new StringBuilder("""
            SELECT tracks.* FROM tracks
            WHERE tracks.pool_type = :visiblePool
              AND NOT EXISTS (
                SELECT 1 FROM hidden_tracks
                WHERE hidden_tracks.user_id = :userId AND hidden_tracks.track_id = tracks.id
              )
            """);
        if (!normalizedQuery.isBlank()) {
            sql.append(" AND (title LIKE :query OR artist LIKE :query OR album LIKE :query)");
        }
        if (genre != null && !genre.isBlank()) {
            sql.append(" AND genre = :genre");
        }
        if (codec != null && !codec.isBlank()) {
            sql.append(" AND UPPER(codec) = :codec");
        }
        if (metadataStatus != null && !metadataStatus.isBlank()) {
            sql.append(" AND metadata_status = :metadataStatus");
        }
        sql.append(switch (normalizedSort) {
            case "ARTIST" -> " ORDER BY artist COLLATE NOCASE, album COLLATE NOCASE, track_number, id";
            case "ALBUM" -> " ORDER BY album COLLATE NOCASE, track_number, normalized_title, id";
            case "NEWEST" -> " ORDER BY created_at DESC, id";
            default -> " ORDER BY normalized_title, id";
        });
        sql.append(" LIMIT :limit OFFSET :offset");

        var statement = jdbcClient.sql(sql.toString())
            .param("limit", limit + 1).param("offset", offset).param("userId", userId)
            .param("visiblePool", libraryPool(childOnly));
        if (!normalizedQuery.isBlank()) {
            statement = statement.param("query", "%" + normalizedQuery + "%");
        }
        if (genre != null && !genre.isBlank()) statement = statement.param("genre", genre);
        if (codec != null && !codec.isBlank()) statement = statement.param("codec", codec.toUpperCase());
        if (metadataStatus != null && !metadataStatus.isBlank()) {
            statement = statement.param("metadataStatus", metadataStatus);
        }

        var results = new ArrayList<>(statement.query(ROW_MAPPER).list());
        String nextCursor = null;
        if (results.size() > limit) {
            results.remove(results.size() - 1);
            nextCursor = String.valueOf(offset + limit);
        }
        return new TrackPageData(results, nextCursor);
    }

    private int parseOffset(String cursor) {
        if (cursor == null || cursor.isBlank()) return 0;
        try {
            return Math.max(0, Integer.parseInt(cursor));
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    @Override
    @Transactional
    public List<TrackRecord> findRandom(int limit, String userId, boolean childOnly) {
        var targetSize = Math.min(Math.max(limit, 0), countRandomCandidates(userId, childOnly));
        if (targetSize == 0) {
            return List.of();
        }

        var scope = childOnly ? "CHILD" : "NORMAL";
        var cycle = currentRandomCycle(userId, scope);
        var selections = new ArrayList<RandomSelection>();
        var first = findUnselectedRandom(
            targetSize, userId, childOnly, scope, cycle, List.of()
        );
        var currentCycle = cycle;
        first.forEach(track -> selections.add(new RandomSelection(track, currentCycle)));

        if (selections.size() < targetSize) {
            cycle = advanceRandomCycle(userId, scope, cycle);
            var selectedIds = selections.stream().map(selection -> selection.track().id()).toList();
            var remaining = findUnselectedRandom(
                targetSize - selections.size(), userId, childOnly, scope, cycle, selectedIds
            );
            var nextCycle = cycle;
            remaining.forEach(track -> selections.add(new RandomSelection(track, nextCycle)));
        }

        var selectedAt = System.currentTimeMillis();
        selections.forEach(selection -> recordRandomSelection(
            userId, scope, selection.track().id(), selection.cycle(), selectedAt
        ));
        return selections.stream().map(RandomSelection::track).toList();
    }

    private int countRandomCandidates(String userId, boolean childOnly) {
        return jdbcClient.sql("""
                SELECT COUNT(*)
                FROM tracks
                WHERE tracks.pool_type = :visiblePool
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId AND hidden_tracks.track_id = tracks.id
                  )
                """)
            .param("userId", userId)
            .param("visiblePool", libraryPool(childOnly))
            .query(Integer.class)
            .single();
    }

    private int currentRandomCycle(String userId, String scope) {
        var now = System.currentTimeMillis();
        jdbcClient.sql("""
                INSERT OR IGNORE INTO random_queue_state(user_id, scope, cycle_no, updated_at)
                VALUES (:userId, :scope, 1, :updatedAt)
                """)
            .param("userId", userId)
            .param("scope", scope)
            .param("updatedAt", now)
            .update();
        jdbcClient.sql("""
                UPDATE random_queue_state SET updated_at = :updatedAt
                WHERE user_id = :userId AND scope = :scope
                """)
            .param("userId", userId)
            .param("scope", scope)
            .param("updatedAt", now)
            .update();
        return jdbcClient.sql("""
                SELECT cycle_no FROM random_queue_state
                WHERE user_id = :userId AND scope = :scope
                """)
            .param("userId", userId)
            .param("scope", scope)
            .query(Integer.class)
            .single();
    }

    private int advanceRandomCycle(String userId, String scope, int currentCycle) {
        var nextCycle = currentCycle + 1;
        jdbcClient.sql("""
                UPDATE random_queue_state
                SET cycle_no = :nextCycle, updated_at = :updatedAt
                WHERE user_id = :userId AND scope = :scope AND cycle_no = :currentCycle
                """)
            .param("nextCycle", nextCycle)
            .param("updatedAt", System.currentTimeMillis())
            .param("userId", userId)
            .param("scope", scope)
            .param("currentCycle", currentCycle)
            .update();
        return nextCycle;
    }

    private List<TrackRecord> findUnselectedRandom(
        int limit, String userId, boolean childOnly, String scope, int cycle,
        List<String> excludedIds
    ) {
        var exclusionFilter = excludedIds.isEmpty() ? "" : " AND tracks.id NOT IN (:excludedIds)\n";
        var statement = jdbcClient.sql("""
                SELECT tracks.*
                FROM tracks
                LEFT JOIN track_play_stats stats ON stats.track_id = tracks.id
                LEFT JOIN random_track_exposures exposure
                  ON exposure.user_id = :userId
                 AND exposure.scope = :scope
                 AND exposure.track_id = tracks.id
                WHERE tracks.pool_type = :visiblePool
                  AND COALESCE(exposure.last_cycle, 0) < :cycle
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId AND hidden_tracks.track_id = tracks.id
                  )
                """ + exclusionFilter + """
                ORDER BY (ABS(RANDOM() % 1000000) / 1000000.0) / (
                    0.15 + 0.85 * CASE
                        WHEN COALESCE(stats.play_count, 0) > 0
                        THEN MIN(100.0, stats.completion_percent_sum / stats.play_count) / 100.0
                        ELSE 0.65
                    END
                ) ASC
                LIMIT :limit
                """)
            .param("limit", limit)
            .param("userId", userId)
            .param("scope", scope)
            .param("cycle", cycle)
            .param("visiblePool", libraryPool(childOnly));
        if (!excludedIds.isEmpty()) {
            statement = statement.param("excludedIds", excludedIds);
        }
        return statement.query(ROW_MAPPER).list();
    }

    private void recordRandomSelection(
        String userId, String scope, String trackId, int cycle, long selectedAt
    ) {
        jdbcClient.sql("""
                INSERT INTO random_track_exposures(
                    user_id, scope, track_id, last_cycle, selected_count, last_selected_at
                ) VALUES (:userId, :scope, :trackId, :cycle, 1, :selectedAt)
                ON CONFLICT(user_id, scope, track_id) DO UPDATE SET
                    last_cycle = excluded.last_cycle,
                    selected_count = random_track_exposures.selected_count + 1,
                    last_selected_at = excluded.last_selected_at
                """)
            .param("userId", userId)
            .param("scope", scope)
            .param("trackId", trackId)
            .param("cycle", cycle)
            .param("selectedAt", selectedAt)
            .update();
    }

    @Override
    public List<TrackRecord> findDiscovery(int limit, String userId, boolean childOnly) {
        return jdbcClient.sql("""
                SELECT tracks.* FROM tracks
                WHERE tracks.pool_type = :visiblePool
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId AND hidden_tracks.track_id = tracks.id
                  )
                ORDER BY RANDOM() LIMIT :limit
                """)
            .param("limit", limit)
            .param("userId", userId)
            .param("visiblePool", childOnly ? "CHILD" : "DISCOVERY")
            .query(ROW_MAPPER)
            .list();
    }

    @Override
    public List<TrackRecord> findManaged(String poolType) {
        var filter = poolType == null || poolType.isBlank() ? "" : " WHERE pool_type = :poolType";
        var statement = jdbcClient.sql("SELECT * FROM tracks" + filter + " ORDER BY created_at DESC");
        if (!filter.isEmpty()) {
            statement = statement.param("poolType", poolType);
        }
        return statement.query(ROW_MAPPER).list();
    }

    @Override
    public List<TrackRecord> findDailyCandidates(
        String poolType, String userId, boolean childOnly
    ) {
        return jdbcClient.sql("""
                SELECT tracks.*
                FROM tracks
                WHERE tracks.pool_type = :poolType
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId AND hidden_tracks.track_id = tracks.id
                  )
                ORDER BY tracks.id
                """)
            .param("poolType", poolType)
            .param("userId", userId)
            .query(ROW_MAPPER)
            .list();
    }

    @Override
    public List<TrackRecord> findMadeForYouCandidates(String userId, boolean childOnly) {
        return jdbcClient.sql("""
                WITH frequent_artists AS (
                    SELECT LOWER(TRIM(history_tracks.artist)) AS artist_key,
                      COUNT(*) AS play_count, MAX(play_history.played_at) AS last_played
                    FROM play_history
                    JOIN tracks history_tracks ON history_tracks.id = play_history.track_id
                    WHERE play_history.user_id = :userId
                      AND history_tracks.pool_type = :visiblePool
                      AND TRIM(history_tracks.artist) <> ''
                      AND NOT EXISTS (
                        SELECT 1 FROM hidden_tracks
                        WHERE hidden_tracks.user_id = :userId
                          AND hidden_tracks.track_id = history_tracks.id
                      )
                    GROUP BY LOWER(TRIM(history_tracks.artist))
                    ORDER BY play_count DESC, last_played DESC, artist_key
                    LIMIT 8
                ), ranked_tracks AS (
                    SELECT tracks.*, frequent_artists.play_count, frequent_artists.last_played,
                      ROW_NUMBER() OVER (
                        PARTITION BY frequent_artists.artist_key ORDER BY tracks.id
                      ) AS artist_position
                    FROM frequent_artists
                    JOIN tracks ON LOWER(TRIM(tracks.artist)) = frequent_artists.artist_key
                    WHERE tracks.pool_type = :visiblePool
                      AND NOT EXISTS (
                        SELECT 1 FROM hidden_tracks
                        WHERE hidden_tracks.user_id = :userId
                          AND hidden_tracks.track_id = tracks.id
                      )
                )
                SELECT * FROM ranked_tracks
                WHERE artist_position <= 100
                ORDER BY play_count DESC, last_played DESC,
                  artist COLLATE NOCASE, id
                """)
            .param("userId", userId)
            .param("visiblePool", libraryPool(childOnly))
            .query(ROW_MAPPER)
            .list();
    }

    @Override
    public boolean hasAudioFeatures(
        String trackId, long fileSize, long modifiedAt, int version
    ) {
        return jdbcClient.sql("""
                SELECT COUNT(*) FROM track_audio_features
                WHERE track_id = :trackId AND file_size = :fileSize
                  AND modified_at = :modifiedAt AND version = :version
                """)
            .param("trackId", trackId)
            .param("fileSize", fileSize)
            .param("modifiedAt", modifiedAt)
            .param("version", version)
            .query(Integer.class)
            .single() == 1;
    }

    @Override
    public void saveAudioFeatures(
        String trackId, long fileSize, long modifiedAt, AudioFeatures features
    ) {
        var now = System.currentTimeMillis();
        jdbcClient.sql("""
                INSERT INTO track_audio_features(
                    track_id, version, file_size, modified_at, vector, created_at, updated_at
                ) VALUES (
                    :trackId, :version, :fileSize, :modifiedAt, :vector, :createdAt, :updatedAt
                )
                ON CONFLICT(track_id) DO UPDATE SET
                    version = excluded.version,
                    file_size = excluded.file_size,
                    modified_at = excluded.modified_at,
                    vector = excluded.vector,
                    updated_at = excluded.updated_at
                """)
            .param("trackId", trackId)
            .param("version", AudioFeatures.VERSION)
            .param("fileSize", fileSize)
            .param("modifiedAt", modifiedAt)
            .param("vector", encodeVector(features.vector()))
            .param("createdAt", now)
            .param("updatedAt", now)
            .update();
    }

    @Override
    public List<AcousticTrackData> findAcousticRecommendationCandidates(
        String userId, boolean childOnly
    ) {
        return jdbcClient.sql("""
                SELECT tracks.*, track_audio_features.vector AS audio_feature_vector,
                  EXISTS (
                    SELECT 1 FROM favorites
                    WHERE favorites.user_id = :userId AND favorites.track_id = tracks.id
                  ) AS favorite
                FROM tracks
                JOIN track_audio_features ON track_audio_features.track_id = tracks.id
                WHERE tracks.pool_type = :visiblePool
                  AND track_audio_features.version = :version
                  AND track_audio_features.file_size = tracks.file_size
                  AND track_audio_features.modified_at = tracks.modified_at
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId
                      AND hidden_tracks.track_id = tracks.id
                  )
                ORDER BY favorite DESC, tracks.id
                """)
            .param("userId", userId)
            .param("visiblePool", libraryPool(childOnly))
            .param("version", AudioFeatures.VERSION)
            .query((resultSet, rowNumber) -> new AcousticTrackData(
                mapTrack(resultSet, rowNumber),
                new AudioFeatures(decodeVector(resultSet.getString("audio_feature_vector"))),
                resultSet.getInt("favorite") == 1
            ))
            .list();
    }

    @Override
    public List<String> findGenres(String userId, boolean childOnly) {
        return jdbcClient.sql("""
                SELECT tracks.genre
                FROM tracks
                WHERE tracks.pool_type = :visiblePool
                  AND tracks.genre <> '未分类'
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId AND hidden_tracks.track_id = tracks.id
                  )
                GROUP BY tracks.genre
                ORDER BY COUNT(*) DESC, tracks.genre
                """)
            .param("userId", userId)
            .param("visiblePool", libraryPool(childOnly))
            .query(String.class)
            .list();
    }

    @Override
    public List<TrackRecord> findByGenre(
        String genre, String userId, boolean childOnly, int limit
    ) {
        return jdbcClient.sql("""
                SELECT tracks.*
                FROM tracks
                LEFT JOIN track_play_stats stats ON stats.track_id = tracks.id
                WHERE tracks.pool_type = :visiblePool
                  AND tracks.genre = :genre
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId AND hidden_tracks.track_id = tracks.id
                  )
                ORDER BY COALESCE(stats.play_count, 0) DESC,
                  CASE WHEN COALESCE(stats.play_count, 0) > 0
                    THEN stats.completion_percent_sum / stats.play_count ELSE 65 END DESC,
                  tracks.normalized_title, tracks.id
                LIMIT :limit
                """)
            .param("genre", genre)
            .param("userId", userId)
            .param("visiblePool", libraryPool(childOnly))
            .param("limit", limit)
            .query(ROW_MAPPER)
            .list();
    }

    @Override
    public List<TrackRecord> findSimilarCandidates(String id, String userId, boolean childOnly) {
        return jdbcClient.sql("""
                SELECT tracks.*
                FROM tracks
                WHERE tracks.id <> :id
                  AND tracks.pool_type = :visiblePool
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId AND hidden_tracks.track_id = tracks.id
                  )
                ORDER BY tracks.updated_at DESC, tracks.id
                LIMIT 1000
                """)
            .param("id", id)
            .param("userId", userId)
            .param("visiblePool", libraryPool(childOnly))
            .query(ROW_MAPPER)
            .list();
    }

    @Override
    public List<ChartTrackData> findChart(
        String region, String userId, boolean childOnly, int limit
    ) {
        var regionFilter = "ALL".equals(region) ? "" : " AND tracks.region = :region\n";
        var statement = jdbcClient.sql("""
                SELECT tracks.*, COALESCE(stats.play_count, 0) AS chart_play_count
                FROM tracks
                LEFT JOIN track_play_stats stats ON stats.track_id = tracks.id
                WHERE tracks.pool_type = :visiblePool
                  AND COALESCE(stats.play_count, 0) > 0
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId AND hidden_tracks.track_id = tracks.id
                  )
                """ + regionFilter + """
                ORDER BY COALESCE(stats.play_count, 0) DESC,
                  CASE WHEN COALESCE(stats.play_count, 0) > 0
                    THEN stats.completion_percent_sum / stats.play_count ELSE 0 END DESC,
                  tracks.normalized_title, tracks.id
                LIMIT :limit
                """)
            .param("userId", userId)
            .param("visiblePool", libraryPool(childOnly))
            .param("limit", limit);
        if (!"ALL".equals(region)) {
            statement = statement.param("region", region);
        }
        return statement.query((resultSet, rowNumber) -> new ChartTrackData(
            mapTrack(resultSet, rowNumber), resultSet.getLong("chart_play_count")
        )).list();
    }

    @Override
    public boolean classify(
        String id, String poolType, String audienceType, String genre, String region
    ) {
        return jdbcClient.sql("""
                UPDATE tracks SET pool_type = :poolType, audience_type = :audienceType,
                    genre = COALESCE(:genre, genre), region = COALESCE(:region, region),
                    updated_at = :updatedAt
                WHERE id = :id
                """)
            .param("id", id)
            .param("poolType", poolType)
            .param("audienceType", audienceType)
            .param("genre", genre)
            .param("region", region)
            .param("updatedAt", System.currentTimeMillis())
            .update() == 1;
    }

    @Override
    public boolean editMetadata(
        String id, String title, String artist, String album, Integer trackNumber, String genre
    ) {
        return editMetadata(id, title, artist, album, trackNumber, genre, null);
    }

    @Override
    public boolean editMetadata(
        String id, String title, String artist, String album, Integer trackNumber, String genre,
        List<String> relatedGenres
    ) {
        return jdbcClient.sql("""
                UPDATE tracks SET title = :title, normalized_title = :normalizedTitle,
                    artist = :artist, album = :album, track_number = :trackNumber,
                    genre = :genre, related_genres = COALESCE(:relatedGenres, related_genres),
                    metadata_status = 'MANUAL', manual_edited = 1,
                    updated_at = :updatedAt
                WHERE id = :id
                """)
            .param("id", id).param("title", title).param("normalizedTitle", TextNormalizer.sortKey(title))
            .param("artist", artist).param("album", album).param("trackNumber", trackNumber)
            .param("genre", genre)
            .param("relatedGenres", relatedGenres == null ? null : encodeGenres(relatedGenres))
            .param("updatedAt", System.currentTimeMillis())
            .update() == 1;
    }

    @Override
    public boolean resetMetadata(String id) {
        return jdbcClient.sql("""
                UPDATE tracks SET manual_edited = 0, metadata_status = 'NEEDS_REVIEW', updated_at = 0
                WHERE id = :id
                """)
            .param("id", id).update() == 1;
    }

    @Override
    public List<TrackRecord> findUnderPath(Path directory) {
        var prefix = directory.toAbsolutePath().normalize().toString();
        return jdbcClient.sql("SELECT * FROM tracks WHERE path = :path OR path LIKE :prefix")
            .param("path", prefix).param("prefix", prefix + java.io.File.separator + "%")
            .query(ROW_MAPPER).list();
    }

    @Override
    @Transactional
    public boolean delete(String id) {
        jdbcClient.sql("DELETE FROM random_track_exposures WHERE track_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM playback_state WHERE track_id = :id").param("id", id).update();
        jdbcClient.sql("""
                UPDATE playback_state
                SET queue_track_ids = trim(
                    replace(',' || queue_track_ids || ',', ',' || :id || ',', ','), ','
                )
                WHERE ',' || queue_track_ids || ',' LIKE '%,' || :id || ',%'
                """).param("id", id).update();
        jdbcClient.sql("DELETE FROM hidden_tracks WHERE track_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM playback_records WHERE track_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM play_history WHERE track_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM track_play_stats WHERE track_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM favorites WHERE track_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM playlist_tracks WHERE track_id = :id").param("id", id).update();
        jdbcClient.sql("DELETE FROM track_audio_features WHERE track_id = :id")
            .param("id", id).update();
        return jdbcClient.sql("DELETE FROM tracks WHERE id = :id").param("id", id).update() == 1;
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
            resultSet.getLong("updated_at"),
            resultSet.getString("pool_type"),
            resultSet.getString("audience_type"),
            resultSet.getString("genre"),
            resultSet.getString("region"),
            decodeGenres(resultSet.getString("related_genres")),
            resultSet.getString("artwork_source")
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

    private static String libraryPool(boolean childOnly) {
        return childOnly ? "CHILD" : "NORMAL";
    }

    private static String encodeGenres(List<String> genres) {
        return String.join("\n", genres == null ? List.of() : genres);
    }

    private static List<String> decodeGenres(String value) {
        return value == null || value.isBlank() ? List.of() : value.lines().toList();
    }

    private static String encodeVector(double[] vector) {
        var result = new StringBuilder();
        for (var index = 0; index < vector.length; index++) {
            if (index > 0) result.append(',');
            result.append(vector[index]);
        }
        return result.toString();
    }

    private static double[] decodeVector(String value) {
        if (value == null || value.isBlank()) return new double[0];
        var parts = value.split(",");
        var result = new double[parts.length];
        for (var index = 0; index < parts.length; index++) {
            result[index] = Double.parseDouble(parts[index]);
        }
        return result;
    }

    private record RandomSelection(TrackRecord track, int cycle) {
    }
}
