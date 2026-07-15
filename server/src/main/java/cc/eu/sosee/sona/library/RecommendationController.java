package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
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
    private static final int DAILY_LIMIT = 60;

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
        var candidates = new ArrayList<>(
            trackStore.findDailyCandidates("DISCOVERY", user.id(), childMode)
        );
        if (candidates.isEmpty()) {
            candidates.addAll(trackStore.findDailyCandidates("NORMAL", user.id(), childMode));
        }
        var today = LocalDate.now(clock.withZone(ZoneId.systemDefault()));
        var seed = Objects.hash(user.id(), today, childMode);
        Collections.shuffle(candidates, new Random(seed));
        return candidates.stream().limit(DAILY_LIMIT).map(TrackResponse::from).toList();
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
}
