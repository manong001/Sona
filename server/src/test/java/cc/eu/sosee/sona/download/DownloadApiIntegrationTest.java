package cc.eu.sosee.sona.download;

import static org.assertj.core.api.Assertions.assertThat;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class DownloadApiIntegrationTest {

    private static final Path ROOT = temporaryDirectory();
    private static HttpServer sidecar;

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("sona.music-dir", () -> ROOT.resolve("music").toString());
        registry.add("sona.data-dir", () -> ROOT.resolve("data").toString());
        registry.add("sona.scan-on-startup", () -> false);
        registry.add("sona.scraping-enabled", () -> false);
        registry.add("sona.auth.bootstrap-username", () -> "admin");
        registry.add("sona.auth.bootstrap-password", () -> "test-password");
        registry.add("sona.downloader.enabled", () -> true);
        registry.add("sona.downloader.base-url", () -> "http://127.0.0.1:" + sidecarPort());
        registry.add("sona.downloader.token", () -> "sidecar-test-token");
    }

    @AfterAll
    static void stopSidecar() {
        if (sidecar != null) {
            sidecar.stop(0);
        }
    }

    @LocalServerPort
    int port;

    private final HttpClient client = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(5))
        .build();

    @Test
    void onlyAdminCanSearchAndQueueDownloads() throws Exception {
        var adminCookie = login("admin", "test-password");
        var created = sendJson(
            "POST",
            "/api/v1/users",
            adminCookie,
            "{\"username\":\"listener\",\"password\":\"listener-password\"}"
        );
        assertThat(created.statusCode()).isEqualTo(201);
        var listenerCookie = login("listener", "listener-password");

        assertThat(get("/api/v1/downloads/search?q=test", listenerCookie).statusCode()).isEqualTo(403);

        var search = get("/api/v1/downloads/search?q=%E6%B5%8B%E8%AF%95", adminCookie);
        assertThat(search.statusCode()).isEqualTo(200);
        assertThat(search.body()).contains("candidate-1", "测试歌曲", "网易云音乐")
            .containsSubsequence(
                "\"candidateId\":\"candidate-large\"",
                "\"candidateId\":\"candidate-1\"",
                "\"candidateId\":\"candidate-small\"",
                "\"candidateId\":\"candidate-unknown\""
            );
        assertThat(search.body()).doesNotContain("secret-download-url");

        var queued = sendJson("POST", "/api/v1/downloads", adminCookie, """
            {"candidateId":"candidate-1","source":"NeteaseMusicClient",
            "sourceName":"网易云音乐","title":"测试歌曲","artist":"测试歌手",
            "album":"测试专辑","extension":"flac","quality":"FLAC · 1411 kbps",
            "durationMs":180000,"fileSizeBytes":12345,"artworkUrl":null,
            "hasLyrics":true,"lyrics":"[00:01.00]歌词"}
            """);
        assertThat(queued.statusCode()).isEqualTo(202);
        var taskId = jsonString(queued.body(), "id");

        String state = "";
        for (var attempt = 0; attempt < 50; attempt++) {
            var tasks = get("/api/v1/downloads", adminCookie);
            assertThat(tasks.statusCode()).isEqualTo(200);
            if (tasks.body().contains("\"id\":\"" + taskId + "\"")
                && tasks.body().contains("\"state\":\"COMPLETED\"")) {
                state = "COMPLETED";
                break;
            }
            Thread.sleep(100);
        }
        assertThat(state).isEqualTo("COMPLETED");
    }

    @Test
    void searchesARequestedMusicSourceWithoutWaitingForOtherSources() throws Exception {
        var adminCookie = login("admin", "test-password");

        var search = get("/api/v1/downloads/search?q=test&sources=QQMusicClient", adminCookie);

        assertThat(search.statusCode()).isEqualTo(200);
        assertThat(search.body()).contains("candidate-small", "QQ音乐").doesNotContain("candidate-1");
    }

    private String login(String username, String password) throws Exception {
        var response = sendJson(
            "POST",
            "/api/v1/auth/login",
            null,
            "{\"username\":\"" + username + "\",\"password\":\"" + password + "\"}"
        );
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
        var builder = HttpRequest.newBuilder(uri(path))
            .header("Content-Type", "application/json")
            .method(method, HttpRequest.BodyPublishers.ofString(body));
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

    private static synchronized int sidecarPort() {
        if (sidecar != null) {
            return sidecar.getAddress().getPort();
        }
        try {
            sidecar = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            sidecar.createContext("/v1/search", exchange -> {
                if (exchange.getRequestURI().getQuery().contains("sources=QQMusicClient")) {
                    respond(exchange, 200, """
                        {"items":[{"candidateId":"candidate-small","source":"QQMusicClient",
                        "sourceName":"QQ音乐","title":"小文件","artist":"测试歌手",
                        "fileSizeBytes":100,"hasLyrics":false}]}
                        """);
                    return;
                }
                respond(exchange, 200, """
                    {"items":[
                    {"candidateId":"candidate-small","source":"QQMusicClient",
                    "sourceName":"QQ音乐","title":"小文件","artist":"测试歌手",
                    "fileSizeBytes":100,"hasLyrics":false},
                    {"candidateId":"candidate-unknown","source":"MiguMusicClient",
                    "sourceName":"咪咕音乐","title":"未知体积","artist":"测试歌手",
                    "fileSizeBytes":null,"hasLyrics":false},
                    {"candidateId":"candidate-1","source":"NeteaseMusicClient",
                    "sourceName":"网易云音乐","title":"测试歌曲","artist":"测试歌手",
                    "album":"测试专辑","extension":"flac","quality":"FLAC · 1411 kbps",
                    "durationMs":180000,"fileSizeBytes":12345,"artworkUrl":null,
                    "hasLyrics":true,"lyrics":"[00:01.00]歌词"},
                    {"candidateId":"candidate-large","source":"KuwoMusicClient",
                    "sourceName":"酷我音乐","title":"大文件","artist":"测试歌手",
                    "fileSizeBytes":99999,"hasLyrics":false}]}
                    """);
            });
            sidecar.createContext("/v1/downloads", exchange -> respond(
                exchange,
                200,
                "{\"files\":[\"Downloads/测试歌曲.flac\"]}"
            ));
            sidecar.setExecutor(Executors.newCachedThreadPool(runnable -> {
                var thread = new Thread(runnable, "fake-musicdl-sidecar");
                thread.setDaemon(true);
                return thread;
            }));
            sidecar.start();
            return sidecar.getAddress().getPort();
        } catch (IOException exception) {
            throw new ExceptionInInitializerError(exception);
        }
    }

    private static void respond(HttpExchange exchange, int status, String body) throws IOException {
        assertThat(exchange.getRequestHeaders().getFirst("X-Sona-Token"))
            .isEqualTo("sidecar-test-token");
        var data = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.sendResponseHeaders(status, data.length);
        exchange.getResponseBody().write(data);
        exchange.close();
    }

    private static Path temporaryDirectory() {
        try {
            var root = Files.createTempDirectory("sona-downloads-");
            Files.createDirectories(root.resolve("music"));
            Files.createDirectories(root.resolve("data"));
            return root;
        } catch (Exception exception) {
            throw new ExceptionInInitializerError(exception);
        }
    }
}
