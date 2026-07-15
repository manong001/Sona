package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.HashSet;
import java.util.List;
import java.util.regex.Pattern;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.jdbc.core.simple.JdbcClient;
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

    @Autowired
    JdbcClient jdbcClient;

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

        jdbcClient.sql("UPDATE tracks SET pool_type = 'NORMAL' WHERE id = 'range-test'").update();
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

    @Test
    void returnsFiftyRandomTracksByDefault() throws Exception {
        var now = System.currentTimeMillis();
        for (var index = 0; index < 60; index++) {
            trackStore.save(new TrackRecord(
                "random-" + index,
                MUSIC_DIRECTORY.resolve("random-" + index + ".mp3"),
                1,
                now,
                "Random " + index,
                "random " + index,
                "Sona",
                "Random",
                index,
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
        }
        jdbcClient.sql("UPDATE tracks SET pool_type = 'NORMAL'").update();

        var login = login("test-password");
        var cookie = login.headers().firstValue("Set-Cookie").orElseThrow().split(";", 2)[0];
        var request = HttpRequest.newBuilder(uri("/api/v1/tracks/random"))
            .header("Cookie", cookie)
            .GET()
            .build();

        var response = send(request);
        var matcher = Pattern.compile("\\\"id\\\":\\\"([^\\\"]+)\\\"").matcher(response.body());
        var ids = new HashSet<String>();
        while (matcher.find()) {
            ids.add(matcher.group(1));
        }

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(ids).hasSize(50);
    }

    @Test
    void recordsPlaybackCompletionRate() throws Exception {
        var now = System.currentTimeMillis();
        trackStore.save(new TrackRecord(
            "completion-rate",
            MUSIC_DIRECTORY.resolve("completion-rate.mp3"),
            1,
            now,
            "Completion Rate",
            "completion rate",
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

        assertThat(postJson(
            "/api/v1/me/history/completion-rate", cookie,
            "{\"listenedMs\":5000,\"progressPercent\":25}"
        ).statusCode()).isEqualTo(204);
        assertThat(postJson(
            "/api/v1/me/history/completion-rate", cookie,
            "{\"listenedMs\":5000,\"progressPercent\":100}"
        ).statusCode()).isEqualTo(204);

        var stats = jdbcClient.sql("""
                SELECT play_count, completion_count
                FROM track_play_stats
                WHERE track_id = 'completion-rate'
                """)
            .query((resultSet, rowNumber) -> List.of(
                resultSet.getInt("play_count"),
                resultSet.getInt("completion_count")
            ))
            .single();
        assertThat(stats).containsExactly(2, 1);
    }

    @Test
    void promotesDiscoveryTrackAfterTenRecentPlaysAverageAboveEightyPercent() throws Exception {
        saveTrack("discovery-nine", "Discovery Nine");
        saveTrack("discovery-eighty", "Discovery Eighty");
        saveTrack("discovery-promoted", "Discovery Promoted");
        trackStore.classify("discovery-nine", "DISCOVERY", "GENERAL");
        trackStore.classify("discovery-eighty", "DISCOVERY", "GENERAL");
        trackStore.classify("discovery-promoted", "DISCOVERY", "GENERAL");
        var cookie = login("test-password").headers().firstValue("Set-Cookie")
            .orElseThrow().split(";", 2)[0];

        recordPlays(cookie, "discovery-nine", 9, 100);
        recordPlays(cookie, "discovery-eighty", 8, 100);
        recordPlays(cookie, "discovery-eighty", 2, 0);
        recordPlays(cookie, "discovery-promoted", 9, 100);
        recordPlays(cookie, "discovery-promoted", 1, 0);

        assertThat(poolType("discovery-nine")).isEqualTo("DISCOVERY");
        assertThat(poolType("discovery-eighty")).isEqualTo("DISCOVERY");
        assertThat(poolType("discovery-promoted")).isEqualTo("NORMAL");
    }

    @Test
    void returnsFavoriteTrackDetailsNewestFirst() throws Exception {
        saveTrack("favorite-older", "Older Favorite");
        saveTrack("favorite-newer", "Newer Favorite");
        var userId = jdbcClient.sql("SELECT id FROM users WHERE username = 'admin'")
            .query(String.class)
            .single();
        jdbcClient.sql("""
                INSERT OR REPLACE INTO favorites(user_id, track_id, created_at)
                VALUES (:userId, :trackId, :createdAt)
                """)
            .param("userId", userId)
            .param("trackId", "favorite-older")
            .param("createdAt", 100)
            .update();
        jdbcClient.sql("""
                INSERT OR REPLACE INTO favorites(user_id, track_id, created_at)
                VALUES (:userId, :trackId, :createdAt)
                """)
            .param("userId", userId)
            .param("trackId", "favorite-newer")
            .param("createdAt", 200)
            .update();
        var login = login("test-password");
        var cookie = login.headers().firstValue("Set-Cookie").orElseThrow().split(";", 2)[0];

        var response = send(HttpRequest.newBuilder(uri("/api/v1/me/favorites/tracks?limit=1"))
            .header("Cookie", cookie)
            .GET()
            .build());

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.body()).contains("\"items\":[");
        assertThat(response.body()).contains("\"id\":\"favorite-newer\"", "\"nextCursor\":\"1\"");
        assertThat(response.body()).doesNotContain("\"id\":\"favorite-older\"");

        var nextPage = send(HttpRequest.newBuilder(uri("/api/v1/me/favorites/tracks?limit=1&cursor=1"))
            .header("Cookie", cookie)
            .GET()
            .build());
        assertThat(nextPage.statusCode()).isEqualTo(200);
        assertThat(nextPage.body()).contains("\"id\":\"favorite-older\"");
    }

    @Test
    void childModeFiltersTracksAndHiddenTrackCannotBeFetchedDirectly() throws Exception {
        saveTrack("general-track", "General Track");
        saveTrack("child-track", "Child Track");
        trackStore.classify("general-track", "NORMAL", "GENERAL");
        trackStore.classify("child-track", "NORMAL", "CHILD");
        var cookie = login("test-password").headers().firstValue("Set-Cookie")
            .orElseThrow().split(";", 2)[0];

        var childList = send(HttpRequest.newBuilder(uri("/api/v1/tracks?childMode=true"))
            .header("Cookie", cookie).GET().build());
        assertThat(childList.body()).contains("child-track").doesNotContain("general-track");

        var hidden = send(HttpRequest.newBuilder(uri("/api/v1/me/tracks/child-track"))
            .header("Cookie", cookie).DELETE().build());
        assertThat(hidden.statusCode()).isEqualTo(204);
        var direct = send(HttpRequest.newBuilder(uri("/api/v1/tracks/child-track"))
            .header("Cookie", cookie).GET().build());
        assertThat(direct.statusCode()).isEqualTo(404);
    }

    @Test
    void returnsDailyGenreRecommendationsAndRegionalChartWithPlayCounts() throws Exception {
        saveTrack("chart-cn-first", "CN First");
        saveTrack("chart-cn-second", "CN Second");
        saveTrack("chart-us", "US Track");
        trackStore.classify("chart-cn-first", "NORMAL", "GENERAL");
        trackStore.classify("chart-cn-second", "NORMAL", "GENERAL");
        trackStore.classify("chart-us", "NORMAL", "CHILD");
        jdbcClient.sql("UPDATE tracks SET genre = 'Pop', region = 'CN' WHERE id LIKE 'chart-cn-%'")
            .update();
        jdbcClient.sql("UPDATE tracks SET genre = 'Rock', region = 'US' WHERE id = 'chart-us'")
            .update();
        var cookie = login("test-password").headers().firstValue("Set-Cookie")
            .orElseThrow().split(";", 2)[0];
        postJson(
            "/api/v1/me/history/chart-cn-first", cookie,
            "{\"listenedMs\":5000,\"progressPercent\":100}"
        );
        postJson(
            "/api/v1/me/history/chart-cn-first", cookie,
            "{\"listenedMs\":5000,\"progressPercent\":100}"
        );
        postJson(
            "/api/v1/me/history/chart-cn-second", cookie,
            "{\"listenedMs\":5000,\"progressPercent\":50}"
        );
        postJson(
            "/api/v1/me/history/chart-us", cookie,
            "{\"listenedMs\":5000,\"progressPercent\":75}"
        );

        var daily = get("/api/v1/recommendations/daily", cookie);
        assertThat(daily.statusCode()).isEqualTo(200);
        assertThat(daily.body()).contains("chart-cn-first", "chart-cn-second", "chart-us");
        assertThat(get("/api/v1/recommendations/daily", cookie).body()).isEqualTo(daily.body());

        var genres = get("/api/v1/recommendations/genres", cookie);
        assertThat(genres.statusCode()).isEqualTo(200);
        assertThat(genres.body()).contains("Pop", "Rock").doesNotContain("未分类");

        var pop = get("/api/v1/recommendations/genres/Pop", cookie);
        assertThat(pop.statusCode()).isEqualTo(200);
        assertThat(pop.body()).contains("chart-cn-first", "chart-cn-second").doesNotContain("chart-us");

        var chart = get("/api/v1/charts?region=CN", cookie);
        assertThat(chart.statusCode()).isEqualTo(200);
        assertThat(chart.body()).containsSubsequence(
            "\"id\":\"chart-cn-first\"", "\"playCount\":2",
            "\"id\":\"chart-cn-second\"", "\"playCount\":1"
        ).doesNotContain("chart-us");

        var childDaily = get("/api/v1/recommendations/daily?childMode=true", cookie);
        assertThat(childDaily.body()).contains("chart-us").doesNotContain("chart-cn-first");
        var childGenres = get("/api/v1/recommendations/genres?childMode=true", cookie);
        assertThat(childGenres.body()).contains("Rock").doesNotContain("Pop");
        var usChart = get("/api/v1/charts?region=US&childMode=true", cookie);
        assertThat(usChart.body()).contains("chart-us", "\"playCount\":1");
    }

    @Test
    void adminCanUpdateTrackGenreAndRegion() throws Exception {
        saveTrack("metadata-admin", "Metadata Admin");
        var cookie = login("test-password").headers().firstValue("Set-Cookie")
            .orElseThrow().split(";", 2)[0];

        var response = patchJson(
            "/api/v1/library/tracks/metadata-admin", cookie,
            "{\"poolType\":\"NORMAL\",\"audienceType\":\"GENERAL\","
                + "\"genre\":\"Jazz\",\"region\":\"US\"}"
        );

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.body()).contains("\"genre\":\"Jazz\"", "\"region\":\"US\"");
    }

    private void saveTrack(String id, String title) {
        var now = System.currentTimeMillis();
        trackStore.save(new TrackRecord(
            id,
            MUSIC_DIRECTORY.resolve(id + ".mp3"),
            1,
            now,
            title,
            title.toLowerCase(),
            "Sona",
            "Favorites",
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

    private HttpResponse<String> post(String path, String cookie) throws Exception {
        return send(HttpRequest.newBuilder(uri(path))
            .header("Cookie", cookie)
            .POST(HttpRequest.BodyPublishers.noBody())
            .build());
    }

    private HttpResponse<String> postJson(String path, String cookie, String body) throws Exception {
        return send(HttpRequest.newBuilder(uri(path))
            .header("Cookie", cookie)
            .header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(body))
            .build());
    }

    private HttpResponse<String> get(String path, String cookie) throws Exception {
        return send(HttpRequest.newBuilder(uri(path))
            .header("Cookie", cookie)
            .GET()
            .build());
    }

    private HttpResponse<String> patchJson(String path, String cookie, String body) throws Exception {
        return send(HttpRequest.newBuilder(uri(path))
            .header("Cookie", cookie)
            .header("Content-Type", "application/json")
            .method("PATCH", HttpRequest.BodyPublishers.ofString(body))
            .build());
    }

    private void recordPlays(String cookie, String trackId, int count, double progressPercent)
        throws Exception {
        for (var index = 0; index < count; index++) {
            assertThat(postJson(
                "/api/v1/me/history/" + trackId, cookie,
                "{\"listenedMs\":5000,\"progressPercent\":" + progressPercent + "}"
            ).statusCode()).isEqualTo(204);
        }
    }

    private String poolType(String trackId) {
        return jdbcClient.sql("SELECT pool_type FROM tracks WHERE id = :trackId")
            .param("trackId", trackId)
            .query(String.class)
            .single();
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
