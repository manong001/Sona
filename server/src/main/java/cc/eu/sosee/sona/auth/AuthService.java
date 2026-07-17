package cc.eu.sosee.sona.auth;

import cc.eu.sosee.sona.config.SonaProperties;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Optional;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
class AuthService {

    private static final SecureRandom SECURE_RANDOM = new SecureRandom();

    private final UserRepository userRepository;
    private final SessionRepository sessionRepository;
    private final PasswordEncoder passwordEncoder;
    private final SonaProperties properties;
    private final Clock clock;

    AuthService(
        UserRepository userRepository,
        SessionRepository sessionRepository,
        PasswordEncoder passwordEncoder,
        SonaProperties properties,
        Clock clock
    ) {
        this.userRepository = userRepository;
        this.sessionRepository = sessionRepository;
        this.passwordEncoder = passwordEncoder;
        this.properties = properties;
        this.clock = clock;
    }

    Optional<AuthSession> login(String username, String password) {
        return userRepository.findByUsername(username)
            .filter(UserAccount::enabled)
            .filter(account -> passwordEncoder.matches(password, account.passwordHash()))
            .map(this::createSession);
    }

    Optional<AuthenticatedUser> authenticate(String rawToken) {
        if (rawToken == null || rawToken.isBlank()) {
            return Optional.empty();
        }
        return sessionRepository.findActiveUser(hash(rawToken));
    }

    void logout(String rawToken) {
        if (rawToken != null && !rawToken.isBlank()) {
            sessionRepository.delete(hash(rawToken));
        }
    }

    void bootstrapAdmin() {
        var username = properties.getAuth().getBootstrapUsername();
        var password = properties.getAuth().getBootstrapPassword();
        if (username == null || username.isBlank() || password == null || password.isBlank()) {
            return;
        }
        var account = userRepository.findByUsername(username)
            .orElseGet(() -> userRepository.create(
                username,
                passwordEncoder.encode(password),
                UserRole.ADMIN
            ));
        userRepository.makeAdmin(account.id());
        sessionRepository.deleteExpired();
    }

    boolean changePassword(AuthenticatedUser user, String currentPassword, String newPassword) {
        var account = userRepository.findById(user.id()).orElse(null);
        if (account == null || !passwordEncoder.matches(currentPassword, account.passwordHash())) {
            return false;
        }
        userRepository.updatePassword(user.id(), passwordEncoder.encode(newPassword));
        sessionRepository.deleteForUser(user.id());
        return true;
    }

    void logoutAll(AuthenticatedUser user) {
        sessionRepository.deleteForUser(user.id());
    }

    private AuthSession createSession(UserAccount account) {
        var tokenBytes = new byte[32];
        SECURE_RANDOM.nextBytes(tokenBytes);
        var rawToken = Base64.getUrlEncoder().withoutPadding().encodeToString(tokenBytes);
        var maxAge = Duration.ofDays(properties.getAuth().getSessionDays());
        sessionRepository.create(hash(rawToken), account.id(), clock.instant().plus(maxAge).toEpochMilli());
        userRepository.recordLogin(account.id());
        return new AuthSession(
            new SessionToken(rawToken, maxAge.toSeconds()),
            account.authenticatedUser()
        );
    }

    private String hash(String value) {
        try {
            var digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }
}
