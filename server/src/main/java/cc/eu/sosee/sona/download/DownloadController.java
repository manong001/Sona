package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.net.URI;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Validated
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
    SearchResponse search(@RequestParam @NotBlank @Size(max = 120) String q) {
        return new SearchResponse(service.search(q));
    }

    @GetMapping
    List<DownloadTask> tasks() {
        return service.tasks();
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
    ResponseEntity<DownloadTask> retry(@PathVariable String id) {
        return ResponseEntity.accepted().body(service.retry(id));
    }

    record SearchResponse(List<DownloadCandidate> items) {
    }
}
