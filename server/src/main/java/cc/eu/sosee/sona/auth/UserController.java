package cc.eu.sosee.sona.auth;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.net.URI;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.CONFLICT;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@RestController
@RequestMapping("/api/v1/users")
class UserController {

    private final UserRepository userRepository;
    private final SessionRepository sessionRepository;
    private final PasswordEncoder passwordEncoder;

    UserController(
        UserRepository userRepository,
        SessionRepository sessionRepository,
        PasswordEncoder passwordEncoder
    ) {
        this.userRepository = userRepository;
        this.sessionRepository = sessionRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @GetMapping
    List<ManagedUserResponse> users() {
        return userRepository.findAll().stream().map(ManagedUserResponse::from).toList();
    }

    @PostMapping
    ResponseEntity<ManagedUserResponse> create(@Valid @RequestBody CreateUserRequest request) {
        if (userRepository.findByUsername(request.username()).isPresent()) {
            throw new ResponseStatusException(CONFLICT, "Username already exists");
        }
        var account = userRepository.create(
            request.username(),
            passwordEncoder.encode(request.password()),
            request.role() == null ? UserRole.USER : request.role()
        );
        return ResponseEntity.created(URI.create("/api/v1/users/" + account.id()))
            .body(ManagedUserResponse.from(account));
    }

    @PatchMapping("/{id}")
    ManagedUserResponse update(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String id,
        @RequestBody UpdateUserRequest request
    ) {
        rejectSelfManagement(actor, id);
        if (!userRepository.setEnabled(id, request.enabled())) {
            throw new ResponseStatusException(NOT_FOUND, "User not found");
        }
        if (!request.enabled()) {
            sessionRepository.deleteForUser(id);
        }
        return ManagedUserResponse.from(userRepository.findById(id).orElseThrow());
    }

    @PatchMapping("/{id}/role")
    ManagedUserResponse updateRole(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String id,
        @Valid @RequestBody UpdateUserRoleRequest request
    ) {
        rejectSelfManagement(actor, id);
        if (!userRepository.setRole(id, request.role())) {
            throw new ResponseStatusException(NOT_FOUND, "User not found");
        }
        return ManagedUserResponse.from(userRepository.findById(id).orElseThrow());
    }

    @PutMapping("/{id}/password")
    ResponseEntity<Void> resetPassword(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String id,
        @Valid @RequestBody ResetPasswordRequest request
    ) {
        rejectSelfManagement(actor, id);
        if (!userRepository.updatePassword(id, passwordEncoder.encode(request.password()))) {
            throw new ResponseStatusException(NOT_FOUND, "User not found");
        }
        sessionRepository.deleteForUser(id);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/{id}")
    ResponseEntity<Void> delete(
        @AuthenticationPrincipal AuthenticatedUser actor,
        @PathVariable String id
    ) {
        rejectSelfManagement(actor, id);
        if (!userRepository.delete(id)) {
            throw new ResponseStatusException(NOT_FOUND, "User not found");
        }
        return ResponseEntity.noContent().build();
    }

    private void rejectSelfManagement(AuthenticatedUser actor, String targetId) {
        if (actor.id().equals(targetId)) {
            throw new ResponseStatusException(CONFLICT, "Administrators cannot manage themselves here");
        }
    }

    record CreateUserRequest(
        @NotBlank @Size(min = 2, max = 32)
        @Pattern(regexp = "^[^\\s/]+$") String username,
        @NotBlank @Size(min = 8, max = 64) String password,
        UserRole role
    ) {
    }

    record UpdateUserRequest(boolean enabled) {
    }

    record UpdateUserRoleRequest(@NotNull UserRole role) {
    }

    record ResetPasswordRequest(@NotBlank @Size(min = 8, max = 64) String password) {
    }

    record ManagedUserResponse(String id, String username, UserRole role, boolean enabled) {

        static ManagedUserResponse from(UserAccount account) {
            return new ManagedUserResponse(
                account.id(),
                account.username(),
                account.role(),
                account.enabled()
            );
        }
    }
}
