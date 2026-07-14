package cc.eu.sosee.sona.library;

import java.nio.file.Path;
import java.util.List;
import java.util.Optional;

interface TrackStore {

    Optional<TrackRecord> findByPath(Path path);

    Optional<TrackRecord> findById(String id);

    void save(TrackRecord track);

    TrackPageData findPage(String query, String cursor, int limit, String userId);

    List<TrackRecord> findRandom(int limit, String userId);

    List<TrackRecord> findDiscovery(int limit, String userId);
}
