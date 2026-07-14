package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@EnabledIfSystemProperty(named = "sona.samples", matches = "true")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class RealSampleApiIntegrationTest {

    private static final Path ROOT = temporaryDirectory();
    private static final Path MUSIC_DIRECTORY = ROOT.resolve("music");
    private static final Path DATA_DIRECTORY = ROOT.resolve("data");
    private static final Path FLAC = MUSIC_DIRECTORY.resolve("01. 邓紫棋 - All About U.flac");
    private static final Path M4A = MUSIC_DIRECTORY.resolve("03. Thank You.m4a");
    private static final Path MP3 = MUSIC_DIRECTORY.resolve("宋冬野 - 郭源潮.mp3");

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("sona.music-dir", () -> MUSIC_DIRECTORY.toString());
        registry.add("sona.data-dir", () -> DATA_DIRECTORY.toString());
        registry.add("sona.scan-on-startup", () -> false);
        registry.add("sona.scraping-enabled", () -> false);
        registry.add("sona.auth.bootstrap-username", () -> "admin");
        registry.add("sona.auth.bootstrap-password", () -> "test-password");
    }

    @BeforeAll
    static void linkSamples() throws Exception {
        Files.createDirectories(MUSIC_DIRECTORY);
        Files.createDirectories(DATA_DIRECTORY);
        Files.createLink(FLAC, Path.of("/Users/leeshun/Downloads/01. 邓紫棋 - All About U.flac"));
        Files.createLink(M4A, Path.of("/Users/leeshun/Downloads/03. Thank You.m4a"));
        Files.createLink(MP3, Path.of("/Users/leeshun/Downloads/宋冬野 - 郭源潮.mp3"));
    }

    @LocalServerPort
    int port;

    @Autowired
    LibraryScanner scanner;

    @Autowired
    TrackStore trackStore;

    private final HttpClient client = HttpClient.newHttpClient();

    @Test
    void scansAndServesRealLosslessAndMp3Samples() throws Exception {
        assertThat(scanner.scan()).isEqualTo(new ScanResult(3, 3, 0, 0, 0));
        var cookie = loginCookie();

        var list = sendText("/api/v1/tracks", cookie);
        assertThat(list.statusCode()).isEqualTo(200);
        assertThat(list.body())
            .contains("All About U")
            .contains("Thank You")
            .contains("郭源潮")
            .contains("\"fileExtension\":\"flac\"")
            .contains("\"fileExtension\":\"m4a\"")
            .contains("\"fileExtension\":\"mp3\"");

        var flacId = trackStore.findByPath(FLAC).orElseThrow().id();
        var rangeRequest = HttpRequest.newBuilder(uri("/api/v1/tracks/" + flacId + "/stream"))
            .header("Cookie", cookie)
            .header("Range", "bytes=0-3")
            .GET()
            .build();
        var range = client.send(rangeRequest, HttpResponse.BodyHandlers.ofByteArray());
        assertThat(range.statusCode()).isEqualTo(206);
        assertThat(new String(range.body(), StandardCharsets.US_ASCII)).isEqualTo("fLaC");

        var artwork = client.send(
            authenticated("/api/v1/tracks/" + flacId + "/artwork", cookie).build(),
            HttpResponse.BodyHandlers.ofByteArray()
        );
        assertThat(artwork.statusCode()).isEqualTo(200);
        assertThat(artwork.body()).isNotEmpty();

        var mp3Id = trackStore.findByPath(MP3).orElseThrow().id();
        var lyrics = sendText("/api/v1/tracks/" + mp3Id + "/lyrics", cookie);
        assertThat(lyrics.statusCode()).isEqualTo(200);
        assertThat(lyrics.body()).contains("[00:24.26]");
    }

    private String loginCookie() throws Exception {
        var request = HttpRequest.newBuilder(uri("/api/v1/auth/login"))
            .header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(
                "{\"username\":\"admin\",\"password\":\"test-password\"}"
            ))
            .build();
        var response = client.send(request, HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isEqualTo(200);
        return response.headers().firstValue("Set-Cookie").orElseThrow().split(";", 2)[0];
    }

    private HttpResponse<String> sendText(String path, String cookie) throws Exception {
        return client.send(authenticated(path, cookie).build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpRequest.Builder authenticated(String path, String cookie) {
        return HttpRequest.newBuilder(uri(path)).header("Cookie", cookie).GET();
    }

    private URI uri(String path) {
        return URI.create("http://127.0.0.1:" + port + path);
    }

    private static Path temporaryDirectory() {
        try {
            return Files.createTempDirectory("sona-real-samples-");
        } catch (Exception exception) {
            throw new ExceptionInInitializerError(exception);
        }
    }
}
