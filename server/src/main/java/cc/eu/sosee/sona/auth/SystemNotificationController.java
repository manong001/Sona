package cc.eu.sosee.sona.auth;

import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/me/notifications")
class SystemNotificationController {

    private final SystemNotificationRepository repository;

    SystemNotificationController(SystemNotificationRepository repository) {
        this.repository = repository;
    }

    @GetMapping
    List<SystemNotificationRepository.SystemNotification> list(
        @AuthenticationPrincipal AuthenticatedUser user
    ) {
        return repository.findRecent(user.id());
    }

    @PutMapping("/{id}/read")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void markRead(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id
    ) {
        if (!repository.markRead(user.id(), id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "通知不存在");
        }
    }

    @PutMapping("/read-all")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void markAllRead(@AuthenticationPrincipal AuthenticatedUser user) {
        repository.markAllRead(user.id());
    }
}
