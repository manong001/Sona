package cc.eu.sosee.sona.library;

import com.github.houbb.opencc4j.util.ZhConverterUtil;
import java.io.IOException;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@Service
class DuplicateTrackService {

    enum DuplicateMatchMode {
        EXACT,
        SIMPLIFIED_TITLE,
        TITLE_WITHOUT_BRACKETS
    }

    private static final Pattern BRACKETED_CONTENT = Pattern.compile(
        "\\([^()]*\\)|（[^（）]*）|\\[[^\\[\\]]*]|【[^【】]*】"
            + "|\\{[^{}]*}|「[^「」]*」|『[^『』]*』"
    );

    private final TrackStore trackStore;
    private final JdbcClient jdbcClient;

    DuplicateTrackService(TrackStore trackStore, JdbcClient jdbcClient) {
        this.trackStore = trackStore;
        this.jdbcClient = jdbcClient;
    }

    List<DuplicateTrackGroup> findDuplicates() {
        return findDuplicates(DuplicateMatchMode.EXACT);
    }

    List<DuplicateTrackGroup> findDuplicates(DuplicateMatchMode mode) {
        var grouped = new LinkedHashMap<DuplicateKey, List<TrackRecord>>();
        for (var track : trackStore.findManaged(null)) {
            var key = duplicateKey(track, mode);
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

    @Transactional
    void replaceAndDelete(String sourceId, String targetId) throws IOException {
        replaceAndDelete(sourceId, targetId, DuplicateMatchMode.EXACT);
    }

    @Transactional
    void replaceAndDelete(
        String sourceId, String targetId, DuplicateMatchMode mode
    ) throws IOException {
        if (sourceId.equals(targetId)) {
            throw new ResponseStatusException(BAD_REQUEST, "Replacement track must be different");
        }
        var source = trackStore.findById(sourceId)
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Track not found"));
        var target = trackStore.findById(targetId)
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Replacement track not found"));
        if (!duplicateKey(source, mode).equals(duplicateKey(target, mode))) {
            throw new ResponseStatusException(BAD_REQUEST, "Tracks are not duplicates");
        }

        copyUniqueReference("favorites", "user_id", "created_at", sourceId, targetId);
        copyUniqueReference("playlist_tracks", "playlist_id", "added_at", sourceId, targetId);
        copyUniqueReference("hidden_tracks", "user_id", "created_at", sourceId, targetId);
        jdbcClient.sql("UPDATE play_history SET track_id = :target WHERE track_id = :source")
            .param("target", targetId).param("source", sourceId).update();
        jdbcClient.sql("UPDATE playback_records SET track_id = :target WHERE track_id = :source")
            .param("target", targetId).param("source", sourceId).update();
        jdbcClient.sql("UPDATE playlists SET artwork_track_id = :target WHERE artwork_track_id = :source")
            .param("target", targetId).param("source", sourceId).update();
        jdbcClient.sql("""
                UPDATE playlist_subscription_items
                SET matched_track_id = :target
                WHERE matched_track_id = :source
                """).param("target", targetId).param("source", sourceId).update();
        jdbcClient.sql("UPDATE playlist_match_choices SET track_id = :target WHERE track_id = :source")
            .param("target", targetId).param("source", sourceId).update();
        jdbcClient.sql("UPDATE playback_state SET track_id = :target WHERE track_id = :source")
            .param("target", targetId).param("source", sourceId).update();
        replaceQueueReferences(sourceId, targetId);
        mergeRandomTrackExposures(sourceId, targetId);
        copyDirectoryMemberships(sourceId, targetId);
        jdbcClient.sql("""
                INSERT INTO track_play_stats(
                    track_id, play_count, completion_count, completion_percent_sum
                )
                SELECT :target, play_count, completion_count, completion_percent_sum
                FROM track_play_stats WHERE track_id = :source
                ON CONFLICT(track_id) DO UPDATE SET
                    play_count = play_count + excluded.play_count,
                    completion_count = completion_count + excluded.completion_count,
                    completion_percent_sum = completion_percent_sum + excluded.completion_percent_sum
                """).param("target", targetId).param("source", sourceId).update();

        if (!trackStore.delete(sourceId)) {
            throw new ResponseStatusException(NOT_FOUND, "Track not found");
        }
        Files.deleteIfExists(source.path());
        if (source.artworkPath() != null && !source.artworkPath().equals(target.artworkPath())) {
            Files.deleteIfExists(source.artworkPath());
        }
    }

    private void copyUniqueReference(
        String table, String ownerColumn, String timeColumn, String sourceId, String targetId
    ) {
        var positionColumns = table.equals("playlist_tracks") ? ", position" : "";
        jdbcClient.sql("INSERT OR IGNORE INTO " + table + "(" + ownerColumn + ", track_id"
                + positionColumns + ", " + timeColumn + ") SELECT " + ownerColumn + ", :target"
                + positionColumns + ", " + timeColumn + " FROM " + table + " WHERE track_id = :source")
            .param("target", targetId).param("source", sourceId).update();
        jdbcClient.sql("DELETE FROM " + table + " WHERE track_id = :source")
            .param("source", sourceId).update();
    }

    private void mergeRandomTrackExposures(String sourceId, String targetId) {
        jdbcClient.sql("""
                INSERT INTO random_track_exposures(
                    user_id, scope, track_id, last_cycle, selected_count, last_selected_at
                )
                SELECT user_id, scope, :target, last_cycle, selected_count, last_selected_at
                FROM random_track_exposures WHERE track_id = :source
                ON CONFLICT(user_id, scope, track_id) DO UPDATE SET
                    last_cycle = max(last_cycle, excluded.last_cycle),
                    selected_count = selected_count + excluded.selected_count,
                    last_selected_at = max(last_selected_at, excluded.last_selected_at)
                """).param("target", targetId).param("source", sourceId).update();
        jdbcClient.sql("DELETE FROM random_track_exposures WHERE track_id = :source")
            .param("source", sourceId).update();
    }

    private void copyDirectoryMemberships(String sourceId, String targetId) {
        jdbcClient.sql("""
                INSERT OR IGNORE INTO directory_track_memberships(directory_path, track_id)
                SELECT directory_path, :target
                FROM directory_track_memberships WHERE track_id = :source
                """).param("target", targetId).param("source", sourceId).update();
        jdbcClient.sql("DELETE FROM directory_track_memberships WHERE track_id = :source")
            .param("source", sourceId).update();
    }

    private void replaceQueueReferences(String sourceId, String targetId) {
        var states = jdbcClient.sql("""
                SELECT user_id, queue_track_ids FROM playback_state
                WHERE ',' || queue_track_ids || ',' LIKE '%,' || :source || ',%'
                """).param("source", sourceId)
            .query((resultSet, rowNumber) -> Map.entry(
                resultSet.getString("user_id"), resultSet.getString("queue_track_ids")
            )).list();
        for (var state : states) {
            var replaced = new LinkedHashSet<String>();
            for (var id : state.getValue().split(",")) {
                if (!id.isBlank()) {
                    replaced.add(id.equals(sourceId) ? targetId : id);
                }
            }
            jdbcClient.sql("UPDATE playback_state SET queue_track_ids = :queue WHERE user_id = :userId")
                .param("queue", String.join(",", replaced)).param("userId", state.getKey()).update();
        }
    }

    private DuplicateKey duplicateKey(TrackRecord track, DuplicateMatchMode mode) {
        var title = switch (mode) {
            case EXACT -> track.title();
            case SIMPLIFIED_TITLE -> ZhConverterUtil.toSimple(track.title());
            case TITLE_WITHOUT_BRACKETS -> withoutBracketedContent(track.title());
        };
        var artist = mode == DuplicateMatchMode.EXACT
            ? ArtistNames.canonical(track.artist())
            : ArtistNames.duplicateCanonical(track.artist());
        return new DuplicateKey(
            TextNormalizer.sortKey(artist),
            TextNormalizer.sortKey(title)
        );
    }

    private String withoutBracketedContent(String value) {
        var result = value;
        String previous;
        do {
            previous = result;
            result = BRACKETED_CONTENT.matcher(result).replaceAll("");
        } while (!result.equals(previous));
        return result;
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
