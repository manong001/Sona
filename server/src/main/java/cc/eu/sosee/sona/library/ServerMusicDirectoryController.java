package cc.eu.sosee.sona.library;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/library/directories")
class ServerMusicDirectoryController {

    private final ServerMusicDirectoryService service;

    ServerMusicDirectoryController(ServerMusicDirectoryService service) {
        this.service = service;
    }

    @GetMapping
    ServerMusicDirectoryListing list(@RequestParam(defaultValue = "") String path) {
        return service.list(path);
    }
}
