package cc.eu.sosee.sona.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class UserSystemApiIntegrationTest {

    private static final Path ROOT = temporaryDirectory();

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("sona.music-dir", () -> ROOT.resolve("music").toString());
        registry.add("sona.data-dir", () -> ROOT.resolve("data").toString());
        registry.add("sona.scan-on-startup", () -> false);
        registry.add("sona.auth.bootstrap-username", () -> "admin");
        registry.add("sona.auth.bootstrap-password", () -> "test-password");
    }

    @LocalServerPort
    int port;

    private final HttpClient client = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(5))
        .build();

    @Test
    void adminCreatesUsersAndNormalUsersCannotManageAccounts() throws Exception {
        var adminCookie = login("admin", "test-password");
        var created = sendJson("POST", "/api/v1/users", adminCookie, """
            {"username":"listener","password":"listener-password"}
            """);

        assertThat(created.statusCode()).isEqualTo(201);
        assertThat(created.body()).contains("\"username\":\"listener\"");
        assertThat(created.body()).contains("\"role\":\"USER\"");
        assertThat(created.body()).contains("\"enabled\":true");

        var listenerCookie = login("listener", "listener-password");
        assertThat(get("/api/v1/users", listenerCookie).statusCode()).isEqualTo(403);
        assertThat(sendJson("POST", "/api/v1/library/scan", listenerCookie, "").statusCode())
            .isEqualTo(403);

        var listenerId = jsonString(created.body(), "id");
        assertThat(sendJson(
            "PATCH",
            "/api/v1/users/" + listenerId,
            adminCookie,
            "{\"enabled\":false}"
        ).statusCode()).isEqualTo(200);
        assertThat(get("/api/v1/auth/me", listenerCookie).statusCode()).isEqualTo(401);
    }

    @Test
    void adminChoosesRoleWhenCreatingUser() throws Exception {
        var adminCookie = login("admin", "test-password");
        var created = sendJson("POST", "/api/v1/users", adminCookie, """
            {"username":"role-admin","password":"role-admin-password","role":"ADMIN"}
            """);

        assertThat(created.statusCode()).isEqualTo(201);
        assertThat(created.body()).contains("\"role\":\"ADMIN\"");

        var createdAdminCookie = login("role-admin", "role-admin-password");
        assertThat(get("/api/v1/users", createdAdminCookie).statusCode()).isEqualTo(200);
    }

    @Test
    void favoritesPlaylistsAndHistoryAreIsolatedPerUser() throws Exception {
        var adminCookie = login("admin", "test-password");
        createUser(adminCookie, "alice");
        createUser(adminCookie, "bob");
        var aliceCookie = login("alice", "account-password");
        var bobCookie = login("bob", "account-password");

        assertThat(sendJson("PUT", "/api/v1/me/favorites/track-1", aliceCookie, "").statusCode())
            .isEqualTo(204);
        assertThat(get("/api/v1/me/favorites", aliceCookie).body()).contains("track-1");
        assertThat(get("/api/v1/me/favorites", bobCookie).body()).doesNotContain("track-1");

        var playlist = sendJson("POST", "/api/v1/me/playlists", aliceCookie, "{\"name\":\"通勤\"}");
        assertThat(playlist.statusCode()).isEqualTo(201);
        var playlistId = jsonString(playlist.body(), "id");
        assertThat(sendJson(
            "PUT",
            "/api/v1/me/playlists/" + playlistId + "/tracks/track-1",
            aliceCookie,
            ""
        ).statusCode()).isEqualTo(204);
        assertThat(get("/api/v1/me/playlists", aliceCookie).body()).contains("通勤", "track-1");
        assertThat(get("/api/v1/me/playlists", bobCookie).body()).doesNotContain("通勤", "track-1");
        assertThat(sendJson(
            "PUT",
            "/api/v1/me/playlists/" + playlistId + "/tracks/track-2",
            bobCookie,
            ""
        ).statusCode()).isEqualTo(404);

        assertThat(sendJson("POST", "/api/v1/me/history/track-1", aliceCookie, "").statusCode())
            .isEqualTo(204);
        assertThat(get("/api/v1/me/history", aliceCookie).body()).contains("track-1");
        assertThat(get("/api/v1/me/history", bobCookie).body()).doesNotContain("track-1");
    }

    @Test
    void changingPasswordRevokesExistingSessions() throws Exception {
        var adminCookie = login("admin", "test-password");
        createUser(adminCookie, "password-user");
        var userCookie = login("password-user", "account-password");

        var changed = sendJson("PUT", "/api/v1/auth/password", userCookie, """
            {"currentPassword":"account-password","newPassword":"new-account-password"}
            """);

        assertThat(changed.statusCode()).isEqualTo(204);
        assertThat(get("/api/v1/auth/me", userCookie).statusCode()).isEqualTo(401);
        assertThat(login("password-user", "new-account-password")).isNotBlank();
    }

    private void createUser(String adminCookie, String username) throws Exception {
        var response = sendJson("POST", "/api/v1/users", adminCookie,
            "{\"username\":\"" + username + "\",\"password\":\"account-password\"}");
        assertThat(response.statusCode()).isEqualTo(201);
    }

    private String login(String username, String password) throws Exception {
        var response = sendJson("POST", "/api/v1/auth/login", null,
            "{\"username\":\"" + username + "\",\"password\":\"" + password + "\"}");
        assertThat(response.statusCode()).isEqualTo(200);
        return response.headers().firstValue("Set-Cookie").orElseThrow().split(";", 2)[0];
    }

    private HttpResponse<String> get(String path, String cookie) throws Exception {
        var builder = HttpRequest.newBuilder(uri(path)).GET();
        if (cookie != null) {
            builder.header("Cookie", cookie);
        }
        return client.send(builder.build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> sendJson(String method, String path, String cookie, String body)
        throws Exception {
        var publisher = body.isEmpty()
            ? HttpRequest.BodyPublishers.noBody()
            : HttpRequest.BodyPublishers.ofString(body);
        var builder = HttpRequest.newBuilder(uri(path))
            .header("Content-Type", "application/json")
            .method(method, publisher);
        if (cookie != null) {
            builder.header("Cookie", cookie);
        }
        return client.send(builder.build(), HttpResponse.BodyHandlers.ofString());
    }

    private URI uri(String path) {
        return URI.create("http://127.0.0.1:" + port + path);
    }

    private String jsonString(String body, String field) {
        var matcher = Pattern.compile("\\\"" + field + "\\\":\\\"([^\\\"]+)\\\"").matcher(body);
        assertThat(matcher.find()).isTrue();
        return matcher.group(1);
    }

    private static Path temporaryDirectory() {
        try {
            var root = Files.createTempDirectory("sona-users-");
            Files.createDirectories(root.resolve("music"));
            Files.createDirectories(root.resolve("data"));
            return root;
        } catch (Exception exception) {
            throw new ExceptionInInitializerError(exception);
        }
    }
}
