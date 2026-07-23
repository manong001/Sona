package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@Validated
@RestController
@RequestMapping("/api/v1/me/playlist-subscriptions")
class PlaylistSubscriptionController {

    private final PlaylistSubscriptionService service;

    PlaylistSubscriptionController(PlaylistSubscriptionService service) {
        this.service = service;
    }

    @GetMapping
    List<PlaylistSubscriptionRepository.Subscription> list(
        @AuthenticationPrincipal AuthenticatedUser user
    ) {
        return service.list(user.id());
    }

    @PostMapping
    ResponseEntity<PlaylistSubscriptionRepository.Subscription> create(
        @AuthenticationPrincipal AuthenticatedUser user,
        @Valid @RequestBody CreateRequest request
    ) {
        return ResponseEntity.accepted().body(service.create(
            user.id(), user.username(), request.sourceUrl(), request.name(), request.poolType(),
            request.autoDownload(), request.syncIntervalHours()
        ));
    }

    @PostMapping("/{id}/sync")
    PlaylistSubscriptionRepository.Subscription sync(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id
    ) {
        return service.sync(user.id(), id);
    }

    @PostMapping("/{id}/download-missing")
    PlaylistSubscriptionRepository.Subscription downloadMissing(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id
    ) {
        return service.downloadMissing(user.id(), id);
    }

    @GetMapping("/{id}/items")
    List<PlaylistSubscriptionService.ItemDetail> items(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id
    ) {
        return service.items(user.id(), id);
    }

    @GetMapping("/{id}/suggestions")
    PlaylistSubscriptionService.ItemPage suggestions(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id,
        @RequestParam(defaultValue = "0") @Min(0) int offset,
        @RequestParam(defaultValue = "40") @Min(1) @Max(100) int limit
    ) {
        return service.suggestedItems(user.id(), id, offset, limit);
    }

    @PostMapping("/{id}/matches/best")
    PlaylistSubscriptionService.BestMatchResult applyBestMatches(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id
    ) {
        return service.applyBestMatches(user.id(), id);
    }

    @PostMapping("/{id}/items/{itemKey}/match")
    PlaylistSubscriptionRepository.Subscription selectMatch(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id,
        @PathVariable String itemKey,
        @Valid @RequestBody MatchRequest request
    ) {
        return service.selectMatch(user.id(), id, itemKey, request.trackId());
    }

    @PostMapping("/{id}/items/{itemKey}/download")
    PlaylistSubscriptionRepository.Subscription downloadItem(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id,
        @PathVariable String itemKey
    ) {
        return service.downloadItem(user.id(), id, itemKey);
    }

    @PatchMapping("/{id}")
    PlaylistSubscriptionRepository.Subscription rename(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id,
        @Valid @RequestBody RenameRequest request
    ) {
        return service.rename(user.id(), id, request.name());
    }

    @DeleteMapping("/{id}")
    ResponseEntity<Void> delete(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id
    ) {
        service.delete(user.id(), id);
        return ResponseEntity.noContent().build();
    }

    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<ErrorResponse> handleResponseStatus(ResponseStatusException exception) {
        var message = exception.getReason() == null ? "歌单订阅失败" : exception.getReason();
        return ResponseEntity.status(exception.getStatusCode()).body(new ErrorResponse(message));
    }

    record CreateRequest(
        @NotBlank @Size(max = 2048) String sourceUrl,
        @Size(max = 80) String name,
        @NotBlank String poolType,
        boolean autoDownload,
        @Min(1) @Max(168) int syncIntervalHours
    ) {
    }

    record RenameRequest(@NotBlank @Size(max = 80) String name) {
    }

    record MatchRequest(@NotBlank String trackId) {
    }

    record ErrorResponse(String error) {
    }
}
