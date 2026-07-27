package cc.eu.sosee.sona.auth;

import org.springframework.stereotype.Service;

@Service
public class UserPreferencesService {

    private final UserPreferencesRepository repository;

    UserPreferencesService(UserPreferencesRepository repository) {
        this.repository = repository;
    }

    public boolean playlistVersionManagementEnabled(String userId) {
        return repository.find(userId)
            .map(stored -> stored.value().playlistVersionManagementEnabled())
            .orElse(false);
    }

    public PlaylistAutomationSettings playlistAutomationSettings(String userId) {
        return repository.find(userId)
            .map(stored -> {
                var value = stored.value();
                return new PlaylistAutomationSettings(
                    value.playlistAutomationEnabled(),
                    value.playlistAutomationIntervalHours(),
                    value.playlistAutomationMatchMode()
                );
            })
            .orElseGet(PlaylistAutomationSettings::disabled);
    }

    public record PlaylistAutomationSettings(
        boolean enabled, int intervalHours, String matchMode
    ) {
        static PlaylistAutomationSettings disabled() {
            return new PlaylistAutomationSettings(false, 2, "IGNORE_BRACKETS");
        }
    }
}
