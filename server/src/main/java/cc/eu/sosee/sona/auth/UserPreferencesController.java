package cc.eu.sosee.sona.auth;

import cc.eu.sosee.sona.download.PlaylistSubscriptionVersionManager;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/me/preferences")
class UserPreferencesController {

    private final UserPreferencesRepository repository;
    private final PlaylistSubscriptionVersionManager versionManager;

    UserPreferencesController(
        UserPreferencesRepository repository,
        PlaylistSubscriptionVersionManager versionManager
    ) {
        this.repository = repository;
        this.versionManager = versionManager;
    }

    @GetMapping
    UserPreferencesResponse get(@AuthenticationPrincipal AuthenticatedUser user) {
        return repository.find(user.id())
            .map(UserPreferencesResponse::configured)
            .orElseGet(UserPreferencesResponse::empty);
    }

    @PutMapping
    UserPreferencesResponse save(
        @AuthenticationPrincipal AuthenticatedUser user,
        @Valid @RequestBody UserPreferencesValue preferences
    ) {
        var wasEnabled = repository.find(user.id())
            .map(stored -> stored.value().playlistVersionManagementEnabled())
            .orElse(false);
        var stored = repository.save(user.id(), preferences);
        if (wasEnabled && !preferences.playlistVersionManagementEnabled()) {
            versionManager.disableForUser(user.id());
        }
        return UserPreferencesResponse.configured(stored);
    }
}

record UserPreferencesValue(
    boolean childMode,
    @NotNull @Pattern(regexp = "boy|girl") String childTheme,
    @NotNull @Pattern(regexp = "floating|fixed") String miniPlayerMode,
    @NotNull @Pattern(regexp = "left|right") String miniPlayerSide,
    @DecimalMin("0.0") double miniPlayerY,
    @NotNull @Pattern(regexp = "off|light|medium|heavy") String hapticStrength,
    @NotNull @Pattern(regexp = "girl|spotify") String appIcon,
    boolean playlistVersionManagementEnabled,
    Boolean playlistAutomationEnabled,
    @Min(1) @Max(168) Integer playlistAutomationIntervalHours,
    @Pattern(regexp = "MANUAL|STRICT|IGNORE_BRACKETS") String playlistAutomationMatchMode
) {
    UserPreferencesValue {
        playlistAutomationEnabled = Boolean.TRUE.equals(playlistAutomationEnabled);
        playlistAutomationIntervalHours = playlistAutomationIntervalHours == null
            ? 2 : playlistAutomationIntervalHours;
        playlistAutomationMatchMode = playlistAutomationMatchMode == null
            ? "IGNORE_BRACKETS" : playlistAutomationMatchMode;
    }
}

record UserPreferencesResponse(
    boolean configured,
    Boolean childMode,
    String childTheme,
    String miniPlayerMode,
    String miniPlayerSide,
    Double miniPlayerY,
    String hapticStrength,
    String appIcon,
    boolean playlistVersionManagementEnabled,
    boolean playlistAutomationEnabled,
    int playlistAutomationIntervalHours,
    String playlistAutomationMatchMode,
    Long updatedAt
) {
    static UserPreferencesResponse empty() {
        return new UserPreferencesResponse(
            false, null, null, null, null, null, null, null,
            false, false, 2, "IGNORE_BRACKETS", null
        );
    }

    static UserPreferencesResponse configured(
        UserPreferencesRepository.StoredUserPreferences stored
    ) {
        var value = stored.value();
        return new UserPreferencesResponse(
            true,
            value.childMode(),
            value.childTheme(),
            value.miniPlayerMode(),
            value.miniPlayerSide(),
            value.miniPlayerY(),
            value.hapticStrength(),
            value.appIcon(),
            value.playlistVersionManagementEnabled(),
            value.playlistAutomationEnabled(),
            value.playlistAutomationIntervalHours(),
            value.playlistAutomationMatchMode(),
            stored.updatedAt()
        );
    }
}
