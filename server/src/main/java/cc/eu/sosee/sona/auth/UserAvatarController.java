package cc.eu.sosee.sona.auth;

import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
class UserAvatarController {

    private final UserAvatarService avatarService;

    UserAvatarController(UserAvatarService avatarService) {
        this.avatarService = avatarService;
    }

    @GetMapping("/api/v1/avatars/{userId}")
    ResponseEntity<byte[]> avatar(@PathVariable String userId) {
        return ResponseEntity.ok()
            .contentType(MediaType.IMAGE_JPEG)
            .cacheControl(CacheControl.noCache())
            .body(avatarService.read(userId));
    }
}
