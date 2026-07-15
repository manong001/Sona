package cc.eu.sosee.sona.auth;

import java.security.Principal;

public record AuthenticatedUser(
    String id, String username, UserRole role, String avatar
) implements Principal {

    public AuthenticatedUser(String id, String username, UserRole role) {
        this(id, username, role, null);
    }

    @Override
    public String getName() {
        return username;
    }
}
