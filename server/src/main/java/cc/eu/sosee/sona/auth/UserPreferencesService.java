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
}
