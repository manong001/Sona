package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Random;
import java.util.Set;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;

@RestController
@RequestMapping("/api/v1")
class RecommendationController {

    private static final Set<String> CHART_REGIONS = Set.of("ALL", "CN", "KR", "US", "JP");
    private static final int DAILY_LIMIT = 180;
    private static final int DAILY_DISCOVERY_LIMIT = 126;
    private static final int DAILY_NORMAL_LIMIT = 54;
    private static final int DAILY_SOURCE_LIMIT = 36;
    private static final int MADE_FOR_YOU_MIX_LIMIT = 2;
    private static final int MADE_FOR_YOU_TRACK_LIMIT = 50;

    private final TrackStore trackStore;
    private final Clock clock;

    RecommendationController(TrackStore trackStore, Clock clock) {
        this.trackStore = trackStore;
        this.clock = clock;
    }

    @GetMapping("/recommendations/daily")
    List<TrackResponse> daily(
        @AuthenticationPrincipal AuthenticatedUser user,
        @RequestParam(defaultValue = "false") boolean childMode
    ) {
        var today = LocalDate.now(clock.withZone(ZoneId.systemDefault()));
        var seed = Objects.hash(user.id(), today, childMode);
        if (childMode) {
            var childTracks = new ArrayList<>(
                trackStore.findDailyCandidates("CHILD", user.id(), true)
            );
            Collections.shuffle(childTracks, new Random(Objects.hash(seed, "child")));
            var selected = new ArrayList<TrackRecord>();
            addDailyTracks(
                childTracks, DAILY_LIMIT, selected, new HashSet<>(), new HashMap<>()
            );
            Collections.shuffle(selected, new Random(Objects.hash(seed, "result")));
            return selected.stream().map(TrackResponse::from).toList();
        }
        var discovery = new ArrayList<>(
            trackStore.findDailyCandidates("DISCOVERY", user.id(), false)
        );
        var normal = new ArrayList<>(
            trackStore.findDailyCandidates("NORMAL", user.id(), false)
        );
        Collections.shuffle(discovery, new Random(Objects.hash(seed, "discovery")));
        Collections.shuffle(normal, new Random(Objects.hash(seed, "normal")));

        var selected = new ArrayList<TrackRecord>();
        var selectedTrackIds = new HashSet<String>();
        var sourceCounts = new HashMap<String, Integer>();
        addDailyTracks(discovery, DAILY_DISCOVERY_LIMIT, selected, selectedTrackIds, sourceCounts);
        addDailyTracks(normal, DAILY_NORMAL_LIMIT, selected, selectedTrackIds, sourceCounts);

        var remaining = new ArrayList<TrackRecord>();
        remaining.addAll(discovery);
        remaining.addAll(normal);
        Collections.shuffle(remaining, new Random(Objects.hash(seed, "remainder")));
        addDailyTracks(
            remaining, DAILY_LIMIT - selected.size(), selected, selectedTrackIds, sourceCounts
        );
        Collections.shuffle(selected, new Random(Objects.hash(seed, "result")));
        return selected.stream().map(TrackResponse::from).toList();
    }

    private void addDailyTracks(
        List<TrackRecord> candidates,
        int limit,
        List<TrackRecord> selected,
        Set<String> selectedTrackIds,
        Map<String, Integer> sourceCounts
    ) {
        var added = 0;
        for (var track : candidates) {
            if (added >= limit || selected.size() >= DAILY_LIMIT) break;
            if (selectedTrackIds.contains(track.id())) continue;
            var source = dailySource(track);
            if (sourceCounts.getOrDefault(source, 0) >= DAILY_SOURCE_LIMIT) continue;
            selected.add(track);
            selectedTrackIds.add(track.id());
            sourceCounts.merge(source, 1, Integer::sum);
            added++;
        }
    }

    private String dailySource(TrackRecord track) {
        if (track.path() == null) return "track:" + track.id();
        var parent = track.path().toAbsolutePath().normalize().getParent();
        return parent == null ? "track:" + track.id() : parent.toString();
    }

    @GetMapping("/recommendations/made-for-you")
    List<MadeForYouMixResponse> madeForYou(
        @AuthenticationPrincipal AuthenticatedUser user,
        @RequestParam(defaultValue = "false") boolean childMode
    ) {
        var acousticCandidates = trackStore.findAcousticRecommendationCandidates(
            user.id(), childMode
        );
        if (acousticCandidates.stream().anyMatch(AcousticTrackData::favorite)) {
            return acousticMixes(acousticCandidates);
        }

        var candidates = trackStore.findMadeForYouCandidates(user.id(), childMode);
        var anchors = new ArrayList<String>();
        for (var candidate : candidates) {
            var artist = ArtistNames.canonical(candidate.artist());
            if (!artist.isBlank() && !anchors.contains(artist)) {
                anchors.add(artist);
                if (anchors.size() == MADE_FOR_YOU_MIX_LIMIT) break;
            }
        }
        if (anchors.isEmpty()) return List.of();

        var groups = new ArrayList<List<TrackRecord>>();
        var assignedTrackIds = new HashSet<String>();
        for (var artist : anchors) {
            var group = new ArrayList<TrackRecord>();
            candidates.stream()
                .filter(track -> ArtistNames.canonical(track.artist()).equals(artist))
                .filter(track -> assignedTrackIds.add(track.id()))
                .findFirst()
                .ifPresent(group::add);
            groups.add(group);
        }

        var remaining = candidates.stream()
            .filter(track -> !assignedTrackIds.contains(track.id()))
            .collect(java.util.stream.Collectors.toCollection(ArrayList::new));
        var groupLanguages = groups.stream()
            .map(group -> TrackLanguage.detect(group.get(0)))
            .toList();
        var today = LocalDate.now(clock.withZone(ZoneId.systemDefault()));
        Collections.shuffle(remaining, new Random(Objects.hash(user.id(), today, childMode, "made")));
        var groupIndex = 0;
        for (var track : remaining) {
            var attempts = 0;
            while (attempts < groups.size()
                && (groups.get(groupIndex).size() >= MADE_FOR_YOU_TRACK_LIMIT
                    || !groupLanguages.get(groupIndex).equals(TrackLanguage.detect(track)))) {
                groupIndex = (groupIndex + 1) % groups.size();
                attempts++;
            }
            if (attempts == groups.size()) continue;
            groups.get(groupIndex).add(track);
            assignedTrackIds.add(track.id());
            groupIndex = (groupIndex + 1) % groups.size();
        }

        var result = new ArrayList<MadeForYouMixResponse>();
        for (var index = 0; index < groups.size(); index++) {
            var tracks = groups.get(index);
            if (!tracks.isEmpty()) {
                result.add(new MadeForYouMixResponse(
                    "made-for-you-" + index,
                    anchors.get(index),
                    tracks.stream().map(TrackResponse::from).toList()
                ));
            }
        }
        return result;
    }

    private List<MadeForYouMixResponse> acousticMixes(
        List<AcousticTrackData> candidates
    ) {
        var favorites = candidates.stream().filter(AcousticTrackData::favorite).toList();
        var recommendations = candidates.stream()
            .filter(candidate -> !candidate.favorite())
            .toList();
        if (recommendations.isEmpty()) return List.of();

        var centers = preferenceCenters(favorites);
        var anchors = centers.stream().map(center -> favorites.stream()
            .min((left, right) -> Double.compare(
                distance(left.features().vector(), center),
                distance(right.features().vector(), center)
            ))
            .orElseThrow()).toList();
        var ranked = new ArrayList<List<AcousticTrackData>>();
        for (var index = 0; index < centers.size(); index++) {
            var center = centers.get(index);
            var language = TrackLanguage.detect(anchors.get(index).track());
            ranked.add(recommendations.stream()
                .filter(candidate -> TrackLanguage.detect(candidate.track()).equals(language))
                .sorted((left, right) -> {
                    var distance = Double.compare(
                        distance(left.features().vector(), center),
                        distance(right.features().vector(), center)
                    );
                    return distance != 0
                        ? distance : left.track().id().compareTo(right.track().id());
                })
                .toList());
        }
        var groups = centers.stream().map(ignored -> new ArrayList<AcousticTrackData>()).toList();
        var positions = new int[centers.size()];
        var assignedTrackIds = new HashSet<String>();
        var madeProgress = true;
        while (madeProgress) {
            madeProgress = false;
            for (var index = 0; index < groups.size(); index++) {
                var group = groups.get(index);
                var choices = ranked.get(index);
                while (group.size() < MADE_FOR_YOU_TRACK_LIMIT
                    && positions[index] < choices.size()) {
                    var choice = choices.get(positions[index]++);
                    if (assignedTrackIds.add(choice.track().id())) {
                        group.add(choice);
                        madeProgress = true;
                        break;
                    }
                }
            }
        }

        var result = new ArrayList<MadeForYouMixResponse>();
        for (var index = 0; index < groups.size(); index++) {
            var tracks = groups.get(index);
            if (tracks.isEmpty()) continue;
            var anchor = anchors.get(index);
            result.add(new MadeForYouMixResponse(
                "made-for-you-acoustic-" + index,
                ArtistNames.canonical(anchor.track().artist()),
                tracks.stream().map(AcousticTrackData::track).map(TrackResponse::from).toList()
            ));
        }
        return result;
    }

    private List<double[]> preferenceCenters(List<AcousticTrackData> favorites) {
        var centerCount = Math.min(MADE_FOR_YOU_MIX_LIMIT, favorites.size());
        var centers = new ArrayList<double[]>();
        centers.add(favorites.get(0).features().vector());
        if (centerCount == 2) {
            var secondCenter = favorites.stream()
                .max((left, right) -> Double.compare(
                    distance(left.features().vector(), centers.get(0)),
                    distance(right.features().vector(), centers.get(0))
                ))
                .orElseThrow().features().vector();
            if (distance(secondCenter, centers.get(0)) > 0.01) centers.add(secondCenter);
        }
        for (var iteration = 0; iteration < 4; iteration++) {
            var assignments = centers.stream()
                .map(ignored -> new ArrayList<double[]>())
                .toList();
            for (var favorite : favorites) {
                var vector = favorite.features().vector();
                var nearest = 0;
                for (var index = 1; index < centers.size(); index++) {
                    if (distance(vector, centers.get(index))
                        < distance(vector, centers.get(nearest))) {
                        nearest = index;
                    }
                }
                assignments.get(nearest).add(vector);
            }
            for (var index = 0; index < centers.size(); index++) {
                if (!assignments.get(index).isEmpty()) {
                    centers.set(index, mean(assignments.get(index)));
                }
            }
        }
        return centers;
    }

    private double[] mean(List<double[]> vectors) {
        var result = new double[vectors.get(0).length];
        for (var vector : vectors) {
            for (var index = 0; index < result.length; index++) result[index] += vector[index];
        }
        var length = 0.0;
        for (var index = 0; index < result.length; index++) {
            result[index] /= vectors.size();
            length += result[index] * result[index];
        }
        length = Math.sqrt(length);
        if (length > 0) {
            for (var index = 0; index < result.length; index++) result[index] /= length;
        }
        return result;
    }

    private double distance(double[] left, double[] right) {
        if (left.length == 0 || left.length != right.length) return Double.POSITIVE_INFINITY;
        var similarity = 0.0;
        for (var index = 0; index < left.length; index++) similarity += left[index] * right[index];
        return 1 - similarity;
    }

    @GetMapping("/recommendations/genres")
    List<String> genres(
        @AuthenticationPrincipal AuthenticatedUser user,
        @RequestParam(defaultValue = "false") boolean childMode
    ) {
        return trackStore.findGenres(user.id(), childMode);
    }

    @GetMapping("/recommendations/genres/{genre}")
    List<TrackResponse> byGenre(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String genre,
        @RequestParam(defaultValue = "20") int limit,
        @RequestParam(defaultValue = "false") boolean childMode
    ) {
        var safeLimit = Math.max(1, Math.min(limit, 50));
        return trackStore.findByGenre(genre, user.id(), childMode, safeLimit).stream()
            .map(TrackResponse::from)
            .toList();
    }

    @GetMapping("/charts")
    List<ChartTrackResponse> chart(
        @AuthenticationPrincipal AuthenticatedUser user,
        @RequestParam(defaultValue = "ALL") String region,
        @RequestParam(defaultValue = "false") boolean childMode
    ) {
        var normalizedRegion = region.toUpperCase();
        if (!CHART_REGIONS.contains(normalizedRegion)) {
            throw new ResponseStatusException(BAD_REQUEST, "Invalid chart region");
        }
        return trackStore.findChart(normalizedRegion, user.id(), childMode, 10).stream()
            .map(item -> new ChartTrackResponse(
                TrackResponse.from(item.track()), item.playCount()
            ))
            .toList();
    }

    record ChartTrackResponse(TrackResponse track, long playCount) {
    }

    record MadeForYouMixResponse(String id, String artist, List<TrackResponse> tracks) {
    }
}
