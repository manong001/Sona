package cc.eu.sosee.sona.library;

import java.nio.file.Path;
import java.util.List;
import java.util.Optional;

interface TrackStore {

    Optional<TrackRecord> findByPath(Path path);

    Optional<TrackRecord> findById(String id);

    Optional<TrackRecord> findVisibleById(String id, String userId);

    void save(TrackRecord track);

    default void save(TrackRecord track, boolean overwriteMetadata) {
        save(track);
    }

    default void save(
        TrackRecord track, boolean overwriteMetadata, boolean overwriteManualMetadata
    ) {
        save(track, overwriteMetadata);
    }

    TrackPageData findPage(
        String query, String cursor, int limit, String userId, boolean childOnly,
        String sort, String genre, String codec, String metadataStatus
    );

    List<TrackRecord> findRandom(int limit, String userId, boolean childOnly);

    List<TrackRecord> findDiscovery(int limit, String userId, boolean childOnly);

    List<TrackRecord> findManaged(String poolType);

    List<TrackRecord> findDailyCandidates(String poolType, String userId, boolean childOnly);

    default List<TrackRecord> findMadeForYouCandidates(String userId, boolean childOnly) {
        return List.of();
    }

    List<String> findGenres(String userId, boolean childOnly);

    List<TrackRecord> findByGenre(String genre, String userId, boolean childOnly, int limit);

    default List<TrackRecord> findSimilarCandidates(String id, String userId, boolean childOnly) {
        return List.of();
    }

    List<ChartTrackData> findChart(String region, String userId, boolean childOnly, int limit);

    boolean classify(
        String id, String poolType, String audienceType, String genre, String region
    );

    boolean editMetadata(
        String id, String title, String artist, String album, Integer trackNumber, String genre
    );

    default boolean editMetadata(
        String id, String title, String artist, String album, Integer trackNumber, String genre,
        List<String> relatedGenres
    ) {
        return editMetadata(id, title, artist, album, trackNumber, genre);
    }

    boolean resetMetadata(String id);

    List<TrackRecord> findUnderPath(Path directory);

    default boolean classify(String id, String poolType, String audienceType) {
        return classify(id, poolType, audienceType, null, null);
    }

    boolean delete(String id);
}
