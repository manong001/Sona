package cc.eu.sosee.sona.auth;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
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

    UserPreferencesController(UserPreferencesRepository repository) {
        this.repository = repository;
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
        return UserPreferencesResponse.configured(repository.save(user.id(), preferences));
    }
}

record UserPreferencesValue(
    boolean childMode,
    @NotNull @Pattern(regexp = "boy|girl") String childTheme,
    @NotNull @Pattern(regexp = "floating|fixed") String miniPlayerMode,
    @NotNull @Pattern(regexp = "left|right") String miniPlayerSide,
    @DecimalMin("0.0") double miniPlayerY,
    @NotNull @Pattern(regexp = "off|light|medium|heavy") String hapticStrength,
    @NotNull @Pattern(regexp = "girl|spotify") String appIcon
) {
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
    Long updatedAt
) {
    static UserPreferencesResponse empty() {
        return new UserPreferencesResponse(
            false, null, null, null, null, null, null, null, null
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
            stored.updatedAt()
        );
    }
}
