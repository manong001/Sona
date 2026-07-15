package cc.eu.sosee.sona.library;

import java.nio.file.Path;
import java.util.List;
import java.util.Optional;

interface TrackStore {

    Optional<TrackRecord> findByPath(Path path);

    Optional<TrackRecord> findById(String id);

    Optional<TrackRecord> findVisibleById(String id, String userId);

    void save(TrackRecord track);

    TrackPageData findPage(String query, String cursor, int limit, String userId, boolean childOnly);

    List<TrackRecord> findRandom(int limit, String userId, boolean childOnly);

    List<TrackRecord> findDiscovery(int limit, String userId, boolean childOnly);

    List<TrackRecord> findManaged(String poolType);

    List<TrackRecord> findDailyCandidates(
        String userId, boolean childOnly, long recentAfter, int limit
    );

    List<String> findGenres(String userId, boolean childOnly);

    List<TrackRecord> findByGenre(String genre, String userId, boolean childOnly, int limit);

    List<ChartTrackData> findChart(String region, String userId, boolean childOnly, int limit);

    boolean classify(
        String id, String poolType, String audienceType, String genre, String region
    );

    default boolean classify(String id, String poolType, String audienceType) {
        return classify(id, poolType, audienceType, null, null);
    }

    boolean delete(String id);
}
