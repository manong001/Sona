package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.net.URI;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/downloads")
class DownloadController {

    private final DownloadService service;

    DownloadController(DownloadService service) {
        this.service = service;
    }

    @GetMapping("/sources")
    List<DownloadSource> sources() {
        return service.sources();
    }

    @GetMapping("/search")
    SearchResponse search(
        @RequestParam String q,
        @RequestParam(required = false) String sources
    ) {
        if (q == null || q.isBlank() || q.length() > 120) {
            throw new ResponseStatusException(
                HttpStatus.BAD_REQUEST, "搜索词长度必须为 1 到 120 个字符"
            );
        }
        var selectedSources = sources == null || sources.isBlank()
            ? List.<String>of()
            : List.of(sources.split(",")).stream().map(String::strip).filter(value -> !value.isEmpty()).toList();
        return new SearchResponse(service.search(q, selectedSources));
    }

    @GetMapping
    List<DownloadTask> tasks(@AuthenticationPrincipal AuthenticatedUser user) {
        return service.tasks(user.username());
    }

    @PostMapping("/playlists/preview")
    DownloadPlaylistPreview previewPlaylist(@Valid @RequestBody PlaylistPreviewRequest request) {
        return service.parsePlaylist(request.url());
    }

    @PostMapping("/playlists")
    ResponseEntity<DownloadService.PlaylistQueueResult> queuePlaylist(
        @AuthenticationPrincipal AuthenticatedUser user,
        @Valid @RequestBody PlaylistQueueRequest request
    ) {
        return ResponseEntity.accepted().body(service.queuePlaylist(
            request.name().strip(), request.items(), user.id(), user.username()
        ));
    }

    @DeleteMapping("/{id}")
    ResponseEntity<Void> delete(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id
    ) {
        service.delete(id, user.username());
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping
    ResponseEntity<Void> clearFailed(@AuthenticationPrincipal AuthenticatedUser user) {
        service.clearFailed(user.username());
        return ResponseEntity.noContent().build();
    }

    @PostMapping
    ResponseEntity<DownloadTask> queue(
        @AuthenticationPrincipal AuthenticatedUser user,
        @Valid @RequestBody DownloadCandidate candidate
    ) {
        var task = service.queue(candidate, user.username());
        return ResponseEntity.accepted()
            .location(URI.create("/api/v1/downloads/" + task.id()))
            .body(task);
    }

    @PostMapping("/{id}/retry")
    ResponseEntity<DownloadTask> retry(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id
    ) {
        return ResponseEntity.accepted().body(service.retry(id, user.username()));
    }

    @PostMapping("/{id}/replacement")
    ResponseEntity<DownloadTask> replace(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id,
        @Valid @RequestBody DownloadCandidate candidate
    ) {
        return ResponseEntity.accepted().body(
            service.replace(id, candidate, user.username())
        );
    }

    record SearchResponse(List<DownloadCandidate> items) {
    }

    record PlaylistPreviewRequest(@NotBlank @Size(max = 2048) String url) {
    }

    record PlaylistQueueRequest(
        @NotBlank @Size(max = 80) String name,
        @NotNull @Size(min = 1, max = 500) List<@Valid DownloadCandidate> items
    ) {
    }
}
