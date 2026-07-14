package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SonaApiIntegrationTest {

    private static final Path ROOT = temporaryDirectory();
    private static final Path MUSIC_DIRECTORY = ROOT.resolve("music");
    private static final Path DATA_DIRECTORY = ROOT.resolve("data");

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("sona.music-dir", () -> MUSIC_DIRECTORY.toString());
        registry.add("sona.data-dir", () -> DATA_DIRECTORY.toString());
        registry.add("sona.scan-on-startup", () -> false);
        registry.add("sona.auth.bootstrap-username", () -> "admin");
        registry.add("sona.auth.bootstrap-password", () -> "test-password");
    }

    @LocalServerPort
    int port;

    @Autowired
    TrackStore trackStore;

    private final HttpClient client = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(5))
        .build();

    @BeforeEach
    void createDirectories() throws Exception {
        Files.createDirectories(MUSIC_DIRECTORY);
        Files.createDirectories(DATA_DIRECTORY);
    }

    @Test
    void rejectsAnonymousRequestsAndAcceptsValidLogin() throws Exception {
        var anonymous = send(HttpRequest.newBuilder(uri("/api/v1/tracks")).GET().build());
        assertThat(anonymous.statusCode()).isEqualTo(401);

        var invalid = login("wrong-password");
        assertThat(invalid.statusCode()).isEqualTo(401);

        var valid = login("test-password");
        assertThat(valid.statusCode()).isEqualTo(200);
        assertThat(valid.headers().firstValue("Set-Cookie")).hasValueSatisfying(cookie -> {
            assertThat(cookie).contains("SONA_SESSION=");
            assertThat(cookie).contains("HttpOnly");
            assertThat(cookie).contains("SameSite=Lax");
        });
    }

    @Test
    void servesRequestedAudioByteRange() throws Exception {
        var audioPath = Files.write(MUSIC_DIRECTORY.resolve("range-test.mp3"), new byte[] {
            0, 1, 2, 3, 4, 5, 6, 7
        });
        var now = System.currentTimeMillis();
        trackStore.save(new TrackRecord(
            "range-test",
            audioPath,
            Files.size(audioPath),
            Files.getLastModifiedTime(audioPath).toMillis(),
            "Range Test",
            "range test",
            "Sona",
            "Tests",
            1,
            1_000,
            "MP3",
            44_100,
            16,
            null,
            null,
            null,
            null,
            "LOCAL",
            false,
            now,
            now
        ));

        var login = login("test-password");
        var cookie = login.headers().firstValue("Set-Cookie").orElseThrow().split(";", 2)[0];
        var request = HttpRequest.newBuilder(uri("/api/v1/tracks/range-test/stream"))
            .header("Cookie", cookie)
            .header("Range", "bytes=2-5")
            .GET()
            .build();

        var response = client.send(request, HttpResponse.BodyHandlers.ofByteArray());

        assertThat(response.statusCode()).isEqualTo(206);
        assertThat(response.headers().firstValue("Accept-Ranges")).contains("bytes");
        assertThat(response.headers().firstValue("Content-Range")).contains("bytes 2-5/8");
        assertThat(response.body()).containsExactly(2, 3, 4, 5);
    }

    private HttpResponse<String> login(String password) throws Exception {
        var request = HttpRequest.newBuilder(uri("/api/v1/auth/login"))
            .header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(
                "{\"username\":\"admin\",\"password\":\"" + password + "\"}"
            ))
            .build();
        return send(request);
    }

    private HttpResponse<String> send(HttpRequest request) throws Exception {
        return client.send(request, HttpResponse.BodyHandlers.ofString());
    }

    private URI uri(String path) {
        return URI.create("http://127.0.0.1:" + port + path);
    }

    private static Path temporaryDirectory() {
        try {
            return Files.createTempDirectory("sona-integration-");
        } catch (Exception exception) {
            throw new ExceptionInInitializerError(exception);
        }
    }
}
