package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.config.SonaProperties;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Comparator;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
class RemoteMetadataScraper implements MetadataScraper {

    private static final Logger LOGGER = LoggerFactory.getLogger(RemoteMetadataScraper.class);
    private static final String USER_AGENT = "Sona/0.1 (http://sosee.eu.cc)";

    private final boolean enabled;
    private final RestClient musicBrainz;
    private final RestClient lrclib;
    private final HttpClient imageClient;
    private long lastMusicBrainzRequestNanos;

    RemoteMetadataScraper(SonaProperties properties) {
        enabled = properties.isScrapingEnabled();
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(5));
        requestFactory.setReadTimeout(Duration.ofSeconds(10));
        musicBrainz = RestClient.builder()
            .baseUrl("https://musicbrainz.org")
            .defaultHeader("User-Agent", USER_AGENT)
            .requestFactory(requestFactory)
            .build();
        lrclib = RestClient.builder()
            .baseUrl("https://lrclib.net")
            .defaultHeader("User-Agent", USER_AGENT)
            .requestFactory(requestFactory)
            .build();
        imageClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();
    }

    @Override
    public ScrapedMetadata scrape(ScrapeRequest request) {
        if (!enabled || blank(request.title()) || blank(request.artist())) {
            return ScrapedMetadata.empty();
        }

        ReleaseMatch release = null;
        if (request.needsAlbum() || request.needsArtwork()) {
            release = findRelease(request);
        }
        var lyrics = request.needsLyrics() ? findLyrics(request) : null;
        var artwork = request.needsArtwork() && release != null ? findArtwork(release.id()) : null;
        return new ScrapedMetadata(
            request.needsAlbum() && release != null ? release.title() : null,
            lyrics == null ? null : lyrics.plainLyrics(),
            lyrics == null ? null : lyrics.syncedLyrics(),
            artwork == null ? null : artwork.data(),
            artwork == null ? null : artwork.mimeType()
        );
    }

    private ReleaseMatch findRelease(ScrapeRequest request) {
        try {
            waitForMusicBrainzRateLimit();
            var query = "recording:\"" + request.title() + "\" AND artist:\"" + request.artist() + "\"";
            var response = musicBrainz.get()
                .uri(builder -> builder
                    .path("/ws/2/recording")
                    .queryParam("query", query)
                    .queryParam("fmt", "json")
                    .queryParam("limit", 10)
                    .build())
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .body(MusicBrainzResponse.class);
            if (response == null || response.recordings() == null) {
                return null;
            }

            var matches = response.recordings().stream()
                .filter(recording -> recording.score() >= 95)
                .filter(recording -> same(recording.title(), request.title()))
                .filter(recording -> durationMatches(recording.length(), request.durationMs()))
                .toList();
            if (matches.size() != 1) {
                return null;
            }
            return chooseRelease(matches.get(0).releases(), request.album());
        } catch (Exception exception) {
            LOGGER.debug("MusicBrainz lookup failed for {} - {}: {}", request.artist(), request.title(), exception.getMessage());
            return null;
        }
    }

    private LyricsResponse findLyrics(ScrapeRequest request) {
        try {
            return lrclib.get()
                .uri(builder -> {
                    var target = builder.path("/api/get")
                        .queryParam("track_name", request.title())
                        .queryParam("artist_name", request.artist())
                        .queryParam("duration", Math.max(0, Math.round(request.durationMs() / 1_000.0)));
                    if (!blank(request.album()) && !"Unknown Album".equals(request.album())) {
                        target.queryParam("album_name", request.album());
                    }
                    return target.build();
                })
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .body(LyricsResponse.class);
        } catch (Exception exception) {
            LOGGER.debug("LRCLIB lookup failed for {} - {}: {}", request.artist(), request.title(), exception.getMessage());
            return null;
        }
    }

    private ArtworkResponse findArtwork(String releaseId) {
        try {
            var request = HttpRequest.newBuilder(
                    URI.create("https://coverartarchive.org/release/" + releaseId + "/front-500")
                )
                .timeout(Duration.ofSeconds(15))
                .header("User-Agent", USER_AGENT)
                .GET()
                .build();
            var response = imageClient.send(request, HttpResponse.BodyHandlers.ofByteArray());
            if (response.statusCode() < 200 || response.statusCode() >= 300 || response.body().length == 0) {
                return null;
            }
            var mimeType = response.headers().firstValue("Content-Type").orElse("image/jpeg").split(";", 2)[0];
            return new ArtworkResponse(response.body(), mimeType);
        } catch (Exception exception) {
            LOGGER.debug("Cover Art Archive lookup failed for {}: {}", releaseId, exception.getMessage());
            return null;
        }
    }

    private ReleaseMatch chooseRelease(List<MusicBrainzRelease> releases, String localAlbum) {
        if (releases == null || releases.isEmpty()) {
            return null;
        }
        var candidates = releases.stream()
            .filter(release -> "Official".equalsIgnoreCase(release.status()))
            .filter(release -> blank(localAlbum)
                || "Unknown Album".equals(localAlbum)
                || same(release.title(), localAlbum))
            .sorted(Comparator.comparing(
                release -> release.date() == null ? "9999" : release.date()
            ))
            .toList();
        if (candidates.isEmpty()) {
            return null;
        }
        var first = candidates.get(0);
        return new ReleaseMatch(first.id(), first.title());
    }

    private synchronized void waitForMusicBrainzRateLimit() throws InterruptedException {
        var oneSecond = Duration.ofSeconds(1).toNanos();
        var elapsed = System.nanoTime() - lastMusicBrainzRequestNanos;
        if (lastMusicBrainzRequestNanos != 0 && elapsed < oneSecond) {
            var remaining = oneSecond - elapsed;
            Thread.sleep(Duration.ofNanos(remaining).toMillis(), (int) (remaining % 1_000_000));
        }
        lastMusicBrainzRequestNanos = System.nanoTime();
    }

    private boolean durationMatches(Long remoteDuration, long localDuration) {
        return remoteDuration == null || localDuration <= 0 || Math.abs(remoteDuration - localDuration) <= 5_000;
    }

    private boolean same(String first, String second) {
        return TextNormalizer.sortKey(first).equals(TextNormalizer.sortKey(second));
    }

    private boolean blank(String value) {
        return value == null || value.isBlank();
    }

    private record MusicBrainzResponse(List<MusicBrainzRecording> recordings) {
    }

    private record MusicBrainzRecording(int score, String title, Long length, List<MusicBrainzRelease> releases) {
    }

    private record MusicBrainzRelease(String id, String title, String status, String date) {
    }

    private record LyricsResponse(String plainLyrics, String syncedLyrics) {
    }

    private record ReleaseMatch(String id, String title) {
    }

    private record ArtworkResponse(byte[] data, String mimeType) {
    }
}
