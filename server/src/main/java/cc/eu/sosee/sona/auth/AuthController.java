package cc.eu.sosee.sona.auth;

import cc.eu.sosee.sona.config.SonaProperties;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Duration;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.security.core.annotation.AuthenticationPrincipal;

import static org.springframework.http.HttpStatus.UNAUTHORIZED;

@RestController
@RequestMapping("/api/v1/auth")
class AuthController {

    private final AuthService authService;
    private final SonaProperties properties;

    AuthController(AuthService authService, SonaProperties properties) {
        this.authService = authService;
        this.properties = properties;
    }

    @PostMapping("/login")
    ResponseEntity<UserResponse> login(@Valid @RequestBody LoginRequest request) {
        var session = authService.login(request.username(), request.password())
            .orElseThrow(() -> new ResponseStatusException(UNAUTHORIZED, "Invalid username or password"));
        var cookie = ResponseCookie.from(SessionAuthenticationFilter.COOKIE_NAME, session.token().value())
            .httpOnly(true)
            .secure(properties.getAuth().isSecureCookie())
            .sameSite("Lax")
            .path("/")
            .maxAge(Duration.ofSeconds(session.token().maxAgeSeconds()))
            .build();
        return ResponseEntity.ok()
            .header(HttpHeaders.SET_COOKIE, cookie.toString())
            .body(UserResponse.from(session.user()));
    }

    @PostMapping("/logout")
    ResponseEntity<Void> logout(HttpServletRequest request) {
        authService.logout(SessionAuthenticationFilter.findCookie(request));
        return ResponseEntity.noContent()
            .header(HttpHeaders.SET_COOKIE, expiredCookie().toString())
            .build();
    }

    @GetMapping("/me")
    UserResponse currentUser(@AuthenticationPrincipal AuthenticatedUser user) {
        return UserResponse.from(user);
    }

    @PutMapping("/password")
    ResponseEntity<Void> changePassword(
        @AuthenticationPrincipal AuthenticatedUser user,
        @Valid @RequestBody ChangePasswordRequest request
    ) {
        if (!authService.changePassword(user, request.currentPassword(), request.newPassword())) {
            throw new ResponseStatusException(UNAUTHORIZED, "Current password is incorrect");
        }
        return ResponseEntity.noContent()
            .header(HttpHeaders.SET_COOKIE, expiredCookie().toString())
            .build();
    }

    @PostMapping("/logout-all")
    ResponseEntity<Void> logoutAll(@AuthenticationPrincipal AuthenticatedUser user) {
        authService.logoutAll(user);
        return ResponseEntity.noContent()
            .header(HttpHeaders.SET_COOKIE, expiredCookie().toString())
            .build();
    }

    private ResponseCookie expiredCookie() {
        return ResponseCookie.from(SessionAuthenticationFilter.COOKIE_NAME, "")
            .httpOnly(true)
            .secure(properties.getAuth().isSecureCookie())
            .sameSite("Lax")
            .path("/")
            .maxAge(Duration.ZERO)
            .build();
    }

    record LoginRequest(@NotBlank String username, @NotBlank String password) {
    }

    record ChangePasswordRequest(
        @NotBlank String currentPassword,
        @NotBlank @Size(min = 8, max = 64) String newPassword
    ) {
    }

    record UserResponse(String id, String username, UserRole role) {

        static UserResponse from(AuthenticatedUser user) {
            return new UserResponse(user.id(), user.username(), user.role());
        }
    }
}
