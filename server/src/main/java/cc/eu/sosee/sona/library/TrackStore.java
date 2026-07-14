package cc.eu.sosee.sona.library;

import java.nio.file.Path;
import java.util.Optional;

interface TrackStore {

    Optional<TrackRecord> findByPath(Path path);

    Optional<TrackRecord> findById(String id);

    void save(TrackRecord track);

    TrackPageData findPage(String query, String cursor, int limit);
}

