package cc.eu.sosee.sona.auth;

import cc.eu.sosee.sona.config.SonaProperties;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import java.security.Principal;
import java.time.Duration;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

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
        var cookie = ResponseCookie.from(SessionAuthenticationFilter.COOKIE_NAME, session.value())
            .httpOnly(true)
            .secure(properties.getAuth().isSecureCookie())
            .sameSite("Lax")
            .path("/")
            .maxAge(Duration.ofSeconds(session.maxAgeSeconds()))
            .build();
        return ResponseEntity.ok()
            .header(HttpHeaders.SET_COOKIE, cookie.toString())
            .body(new UserResponse(request.username()));
    }

    @PostMapping("/logout")
    ResponseEntity<Void> logout(HttpServletRequest request) {
        authService.logout(SessionAuthenticationFilter.findCookie(request));
        var expiredCookie = ResponseCookie.from(SessionAuthenticationFilter.COOKIE_NAME, "")
            .httpOnly(true)
            .secure(properties.getAuth().isSecureCookie())
            .sameSite("Lax")
            .path("/")
            .maxAge(Duration.ZERO)
            .build();
        return ResponseEntity.noContent()
            .header(HttpHeaders.SET_COOKIE, expiredCookie.toString())
            .build();
    }

    @GetMapping("/me")
    UserResponse currentUser(Principal principal) {
        return new UserResponse(principal.getName());
    }

    record LoginRequest(@NotBlank String username, @NotBlank String password) {
    }

    record UserResponse(String username) {
    }
}

