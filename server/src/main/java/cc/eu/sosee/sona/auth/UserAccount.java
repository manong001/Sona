package cc.eu.sosee.sona.auth;

record UserAccount(String id, String username, String passwordHash, UserRole role, boolean enabled) {

    AuthenticatedUser authenticatedUser() {
        return new AuthenticatedUser(id, username, role);
    }
}
