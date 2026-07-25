package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@RestController
@RequestMapping("/api/v1/recommendations")
class RecommendationExperienceController {

    private final TrackStore trackStore;
    private final RecommendationPreferenceRepository preferences;

    RecommendationExperienceController(
        TrackStore trackStore, RecommendationPreferenceRepository preferences
    ) {
        this.trackStore = trackStore;
        this.preferences = preferences;
    }

    @GetMapping("/discovery-feed")
    List<RecommendedTrackResponse> discoveryFeed(
        @AuthenticationPrincipal AuthenticatedUser user,
        @RequestParam(defaultValue = "20") int limit,
        @RequestParam(defaultValue = "false") boolean childMode
    ) {
        var safeLimit = safeLimit(limit);
        return preferences.allowed(
                user.id(), trackStore.findDiscovery(Math.min(50, safeLimit * 3), user.id(), childMode)
            ).stream()
            .limit(safeLimit)
            .map(track -> recommended(track, discoveryReason(track), "DISCOVERY"))
            .toList();
    }

    @GetMapping("/similar/{id}")
    List<RecommendedTrackResponse> similar(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id,
        @RequestParam(defaultValue = "20") int limit,
        @RequestParam(defaultValue = "false") boolean childMode
    ) {
        var target = trackStore.findVisibleById(id, user.id())
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Track not found"));
        var candidates = preferences.allowed(
            user.id(), trackStore.findSimilarCandidates(id, user.id(), childMode)
        );
        return SimilarTrackService.rank(target, target.relatedGenres(), candidates, safeLimit(limit))
            .stream()
            .map(track -> recommended(
                track, "与《" + target.title() + "》的曲风或艺人相近", "SIMILAR"
            ))
            .toList();
    }

    @GetMapping("/scenes/{scene}")
    List<RecommendedTrackResponse> scene(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String scene,
        @RequestParam(defaultValue = "50") int limit,
        @RequestParam(defaultValue = "false") boolean childMode
    ) {
        var profile = SceneProfile.from(scene);
        var childOnly = childMode || profile == SceneProfile.CHILD;
        var candidates = preferences.allowedAcoustic(
            user.id(), trackStore.findAcousticRecommendationCandidates(user.id(), childOnly)
        );
        var withMeasurements = candidates.stream()
            .filter(item -> item.features().tempoBpm() > 0)
            .filter(profile::accepts)
            .sorted(Comparator.comparingDouble(profile::distance)
                .thenComparing(item -> item.track().id()))
            .toList();
        var selected = new ArrayList<AcousticTrackData>(
            withMeasurements.isEmpty() ? candidates : withMeasurements
        );
        return selected.stream()
            .limit(safeLimit(limit))
            .map(item -> recommended(
                item.track(), profile.reason(item.features(), withMeasurements.isEmpty()), "SCENE"
            ))
            .toList();
    }

    private int safeLimit(int limit) {
        return Math.max(1, Math.min(limit, 50));
    }

    private RecommendedTrackResponse recommended(TrackRecord track, String reason, String source) {
        return new RecommendedTrackResponse(TrackResponse.from(track), reason, source);
    }

    private String discoveryReason(TrackRecord track) {
        return "未分类".equals(track.genre())
            ? "来自发现池，优先探索较少听到的歌曲"
            : "来自发现池的" + track.genre() + "歌曲";
    }

    record RecommendedTrackResponse(TrackResponse track, String reason, String source) {
    }

    private enum SceneProfile {
        FOCUS(60, 115, 88, 0.18, 0.58, 0.36, "适合专注"),
        COMMUTE(75, 155, 112, 0.30, 0.86, 0.58, "适合通勤"),
        WORKOUT(108, 190, 142, 0.52, 1.00, 0.76, "高能运动节奏"),
        SLEEP(50, 100, 72, 0.00, 0.38, 0.20, "低能量睡眠陪伴"),
        LATE_NIGHT(55, 125, 86, 0.10, 0.62, 0.36, "适合深夜"),
        CHILD(55, 170, 105, 0.10, 0.90, 0.52, "儿童歌曲池");

        private final double minBpm;
        private final double maxBpm;
        private final double targetBpm;
        private final double minEnergy;
        private final double maxEnergy;
        private final double targetEnergy;
        private final String title;

        SceneProfile(
            double minBpm, double maxBpm, double targetBpm,
            double minEnergy, double maxEnergy, double targetEnergy, String title
        ) {
            this.minBpm = minBpm;
            this.maxBpm = maxBpm;
            this.targetBpm = targetBpm;
            this.minEnergy = minEnergy;
            this.maxEnergy = maxEnergy;
            this.targetEnergy = targetEnergy;
            this.title = title;
        }

        boolean accepts(AcousticTrackData item) {
            return item.features().tempoBpm() >= minBpm
                && item.features().tempoBpm() <= maxBpm
                && item.features().energy() >= minEnergy
                && item.features().energy() <= maxEnergy;
        }

        double distance(AcousticTrackData item) {
            return Math.abs(item.features().tempoBpm() - targetBpm) / 140
                + Math.abs(item.features().energy() - targetEnergy);
        }

        String reason(AudioFeatures features, boolean fallback) {
            if (fallback || features.tempoBpm() <= 0) {
                return title + " · 等待下次完整扫描补充节奏分析";
            }
            return title + " · " + Math.round(features.tempoBpm()) + " BPM";
        }

        static SceneProfile from(String value) {
            try {
                return valueOf(value.strip().toUpperCase());
            } catch (IllegalArgumentException exception) {
                throw new ResponseStatusException(BAD_REQUEST, "Unknown scene");
            }
        }
    }
}
