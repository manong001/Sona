package cc.eu.sosee.sona.library;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/library/scan")
class ScanController {

    private final ScanCoordinator coordinator;

    ScanController(ScanCoordinator coordinator) {
        this.coordinator = coordinator;
    }

    @PostMapping
    ResponseEntity<ScanStatus> start(@RequestParam(defaultValue = "") String path) {
        return ResponseEntity.accepted().body(coordinator.start(path));
    }

    @GetMapping("/status")
    ScanStatus status() {
        return coordinator.status();
    }
}
