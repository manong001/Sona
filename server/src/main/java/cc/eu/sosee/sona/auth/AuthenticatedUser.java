package cc.eu.sosee.sona.auth;

import java.security.Principal;

public record AuthenticatedUser(String id, String username, UserRole role) implements Principal {

    @Override
    public String getName() {
        return username;
    }
}
