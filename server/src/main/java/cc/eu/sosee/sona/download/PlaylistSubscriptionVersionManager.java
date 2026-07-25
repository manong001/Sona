package cc.eu.sosee.sona.download;

import org.springframework.stereotype.Component;

@Component
public class PlaylistSubscriptionVersionManager {

    private final PlaylistSubscriptionService service;

    PlaylistSubscriptionVersionManager(PlaylistSubscriptionService service) {
        this.service = service;
    }

    public void disableForUser(String userId) {
        service.disableVersionManagement(userId);
    }
}
