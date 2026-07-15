package cc.eu.sosee.sona.auth;

record UserAccount(
    String id, String username, String passwordHash, UserRole role, boolean enabled, String avatar
) {

    AuthenticatedUser authenticatedUser() {
        return new AuthenticatedUser(id, username, role, avatar);
    }
}
