package cc.eu.sosee.sona.library;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;

@RestController
@RequestMapping("/api/v1/library/scan")
class ScanController {

    private final ScanCoordinator coordinator;

    ScanController(ScanCoordinator coordinator) {
        this.coordinator = coordinator;
    }

    @PostMapping
    ResponseEntity<ScanStatus> start(
        @RequestParam(defaultValue = "") String path,
        @RequestParam(defaultValue = "MISSING_ONLY") ScrapeMode mode
    ) {
        if (mode == ScrapeMode.FORCE_OVERWRITE) {
            throw new ResponseStatusException(BAD_REQUEST, "强制覆盖仅支持歌单刮削");
        }
        return ResponseEntity.accepted().body(coordinator.start(path, mode));
    }

    @GetMapping("/status")
    ScanStatus status() {
        return coordinator.status();
    }
}
