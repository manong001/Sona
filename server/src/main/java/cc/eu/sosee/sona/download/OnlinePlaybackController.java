package cc.eu.sosee.sona.download;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/online-playback/sources")
class OnlinePlaybackController {

    private final OnlinePlaybackService service;

    OnlinePlaybackController(OnlinePlaybackService service) {
        this.service = service;
    }

    @GetMapping
    List<OnlinePlaybackSource> sources() {
        return service.sources();
    }

    @PutMapping("/{id}")
    void setEnabled(@PathVariable String id, @Valid @RequestBody UpdateSourceRequest request) {
        service.setEnabled(id, request.enabled());
    }

    record UpdateSourceRequest(boolean enabled) {
    }
}
