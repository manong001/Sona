package cc.eu.sosee.sona.auth;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

@Component
@Order(1)
class AuthBootstrap implements ApplicationRunner {

    private final AuthService authService;

    AuthBootstrap(AuthService authService) {
        this.authService = authService;
    }

    @Override
    public void run(ApplicationArguments arguments) {
        authService.bootstrapAdmin();
    }
}
