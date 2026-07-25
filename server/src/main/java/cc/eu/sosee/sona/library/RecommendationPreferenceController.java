package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@RestController
@RequestMapping("/api/v1/me/recommendations")
class RecommendationPreferenceController {

    private final RecommendationPreferenceRepository preferences;
    private final TrackStore trackStore;

    RecommendationPreferenceController(
        RecommendationPreferenceRepository preferences, TrackStore trackStore
    ) {
        this.preferences = preferences;
        this.trackStore = trackStore;
    }

    @GetMapping
    RecommendationPreferenceRepository.RecommendationPreferences preferences(
        @AuthenticationPrincipal AuthenticatedUser user
    ) {
        return preferences.preferences(user.id());
    }

    @PutMapping
    RecommendationPreferenceRepository.RecommendationPreferences update(
        @AuthenticationPrincipal AuthenticatedUser user,
        @Valid @RequestBody RecommendationSettingsRequest request
    ) {
        preferences.setPersonalizedEnabled(user.id(), request.personalizedEnabled());
        return preferences.preferences(user.id());
    }

    @PostMapping("/feedback")
    RecommendationPreferenceRepository.RecommendationFeedback addFeedback(
        @AuthenticationPrincipal AuthenticatedUser user,
        @Valid @RequestBody RecommendationFeedbackRequest request
    ) {
        var track = trackStore.findVisibleById(request.trackId(), user.id())
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Track not found"));
        var target = switch (request.type()) {
            case TRACK -> new Target(track.id(), track.title());
            case ARTIST -> new Target(ArtistNames.canonical(track.artist()), track.artist());
            case GENRE -> new Target(track.genre(), track.genre());
        };
        if (target.value() == null || target.value().isBlank()
            || request.type() == RecommendationPreferenceRepository.FeedbackTargetType.GENRE
                && "未分类".equals(target.value())) {
            throw new ResponseStatusException(BAD_REQUEST, "Track has no usable feedback target");
        }
        return preferences.add(user.id(), request.type(), target.value(), target.display());
    }

    @DeleteMapping("/feedback/{id}")
    ResponseEntity<Void> removeFeedback(
        @AuthenticationPrincipal AuthenticatedUser user, @PathVariable String id
    ) {
        if (!preferences.remove(user.id(), id)) {
            throw new ResponseStatusException(NOT_FOUND, "Feedback not found");
        }
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/feedback")
    ResponseEntity<Void> clearFeedback(@AuthenticationPrincipal AuthenticatedUser user) {
        preferences.clear(user.id());
        return ResponseEntity.noContent().build();
    }

    record RecommendationSettingsRequest(boolean personalizedEnabled) {
    }

    record RecommendationFeedbackRequest(
        @NotNull RecommendationPreferenceRepository.FeedbackTargetType type,
        @NotBlank String trackId
    ) {
    }

    private record Target(String value, String display) {
    }
}
