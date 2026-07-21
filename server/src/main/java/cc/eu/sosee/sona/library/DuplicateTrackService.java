package cc.eu.sosee.sona.library;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

@Service
class DuplicateTrackService {

    private final TrackStore trackStore;
    private final JdbcClient jdbcClient;

    DuplicateTrackService(TrackStore trackStore, JdbcClient jdbcClient) {
        this.trackStore = trackStore;
        this.jdbcClient = jdbcClient;
    }

    List<DuplicateTrackGroup> findDuplicates() {
        var grouped = new LinkedHashMap<DuplicateKey, List<TrackRecord>>();
        for (var track : trackStore.findManaged(null)) {
            var artist = ArtistNames.canonical(track.artist());
            var key = new DuplicateKey(
                TextNormalizer.sortKey(artist), TextNormalizer.sortKey(track.title())
            );
            if (key.artist().isBlank() || key.title().isBlank()
                || "unknown artist".equals(key.artist())
                || "unknown title".equals(key.title())) {
                continue;
            }
            grouped.computeIfAbsent(key, ignored -> new ArrayList<>()).add(track);
        }

        var duplicateIds = grouped.values().stream()
            .filter(tracks -> tracks.size() > 1)
            .flatMap(List::stream)
            .map(TrackRecord::id)
            .collect(java.util.stream.Collectors.toSet());
        var usage = usageByTrack(duplicateIds);

        return grouped.values().stream()
            .filter(tracks -> tracks.size() > 1)
            .map(tracks -> group(tracks, usage))
            .sorted(Comparator.comparing(DuplicateTrackGroup::artist, String.CASE_INSENSITIVE_ORDER)
                .thenComparing(DuplicateTrackGroup::title, String.CASE_INSENSITIVE_ORDER))
            .toList();
    }

    private DuplicateTrackGroup group(
        List<TrackRecord> tracks,
        Map<String, List<DuplicateTrackUsage>> usage
    ) {
        var sorted = tracks.stream()
            .sorted(Comparator.comparing(track -> track.path().toString()))
            .toList();
        var first = sorted.get(0);
        return new DuplicateTrackGroup(
            ArtistNames.canonical(first.artist()),
            first.title(),
            sorted.stream().map(track -> new DuplicateTrackItem(
                TrackResponse.from(track),
                track.path().toString(),
                track.fileSize(),
                usage.getOrDefault(track.id(), List.of())
            )).toList()
        );
    }

    private Map<String, List<DuplicateTrackUsage>> usageByTrack(Set<String> duplicateIds) {
        if (duplicateIds.isEmpty()) {
            return Map.of();
        }

        var accumulators = new HashMap<UsageKey, UsageAccumulator>();
        jdbcClient.sql("""
                SELECT favorites.track_id, users.id AS user_id, users.username
                FROM favorites JOIN users ON users.id = favorites.user_id
                """)
            .query((resultSet, rowNumber) -> new UsageRow(
                resultSet.getString("track_id"), resultSet.getString("user_id"),
                resultSet.getString("username"), null
            ))
            .list().stream()
            .filter(row -> duplicateIds.contains(row.trackId()))
            .forEach(row -> usage(accumulators, row).favorite = true);

        jdbcClient.sql("""
                SELECT playlist_tracks.track_id, users.id AS user_id, users.username,
                       playlists.name AS detail
                FROM playlist_tracks
                JOIN playlists ON playlists.id = playlist_tracks.playlist_id
                JOIN users ON users.id = playlists.user_id
                WHERE playlists.directory_path IS NULL
                """)
            .query((resultSet, rowNumber) -> new UsageRow(
                resultSet.getString("track_id"), resultSet.getString("user_id"),
                resultSet.getString("username"), resultSet.getString("detail")
            ))
            .list().stream()
            .filter(row -> duplicateIds.contains(row.trackId()))
            .forEach(row -> usage(accumulators, row).playlists.add(row.detail()));

        jdbcClient.sql("""
                SELECT DISTINCT play_history.track_id, users.id AS user_id, users.username
                FROM play_history JOIN users ON users.id = play_history.user_id
                """)
            .query((resultSet, rowNumber) -> new UsageRow(
                resultSet.getString("track_id"), resultSet.getString("user_id"),
                resultSet.getString("username"), null
            ))
            .list().stream()
            .filter(row -> duplicateIds.contains(row.trackId()))
            .forEach(row -> usage(accumulators, row).history = true);

        jdbcClient.sql("""
                SELECT playback_state.track_id, playback_state.queue_track_ids,
                       users.id AS user_id, users.username
                FROM playback_state JOIN users ON users.id = playback_state.user_id
                """)
            .query((resultSet, rowNumber) -> new PlaybackUsageRow(
                resultSet.getString("track_id"), resultSet.getString("queue_track_ids"),
                resultSet.getString("user_id"), resultSet.getString("username")
            ))
            .list()
            .forEach(row -> {
                var trackIds = new LinkedHashSet<String>();
                trackIds.add(row.trackId());
                if (row.queueTrackIds() != null && !row.queueTrackIds().isBlank()) {
                    trackIds.addAll(List.of(row.queueTrackIds().split(",")));
                }
                trackIds.stream().filter(duplicateIds::contains).forEach(trackId -> {
                    var usageRow = new UsageRow(trackId, row.userId(), row.username(), null);
                    usage(accumulators, usageRow).currentQueue = true;
                });
            });

        var result = new HashMap<String, List<DuplicateTrackUsage>>();
        accumulators.forEach((key, value) -> result
            .computeIfAbsent(key.trackId(), ignored -> new ArrayList<>())
            .add(value.toResponse(key)));
        result.values().forEach(values -> values.sort(
            Comparator.comparing(DuplicateTrackUsage::username, String.CASE_INSENSITIVE_ORDER)
        ));
        return result;
    }

    private UsageAccumulator usage(
        Map<UsageKey, UsageAccumulator> accumulators,
        UsageRow row
    ) {
        return accumulators.computeIfAbsent(
            new UsageKey(row.trackId(), row.userId(), row.username()),
            ignored -> new UsageAccumulator()
        );
    }

    record DuplicateTrackGroup(String artist, String title, List<DuplicateTrackItem> tracks) {
    }

    record DuplicateTrackItem(
        TrackResponse track,
        String path,
        long fileSize,
        List<DuplicateTrackUsage> users
    ) {
    }

    record DuplicateTrackUsage(
        String userId,
        String username,
        boolean favorite,
        List<String> playlists,
        boolean history,
        boolean currentQueue
    ) {
    }

    private record DuplicateKey(String artist, String title) {
    }

    private record UsageKey(String trackId, String userId, String username) {
    }

    private record UsageRow(String trackId, String userId, String username, String detail) {
    }

    private record PlaybackUsageRow(
        String trackId, String queueTrackIds, String userId, String username
    ) {
    }

    private static final class UsageAccumulator {
        private boolean favorite;
        private final Set<String> playlists = new LinkedHashSet<>();
        private boolean history;
        private boolean currentQueue;

        private DuplicateTrackUsage toResponse(UsageKey key) {
            return new DuplicateTrackUsage(
                key.userId(), key.username(), favorite, List.copyOf(playlists), history, currentQueue
            );
        }
    }
}
