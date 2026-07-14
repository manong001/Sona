package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.config.SonaProperties;
import cc.eu.sosee.sona.download.DownloadCandidate;
import cc.eu.sosee.sona.download.DownloaderGateway;
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
    private final DownloaderGateway downloaderGateway;
    private long lastMusicBrainzRequestNanos;

    RemoteMetadataScraper(SonaProperties properties, DownloaderGateway downloaderGateway) {
        enabled = properties.isScrapingEnabled();
        this.downloaderGateway = downloaderGateway;
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
        if (!enabled || blank(request.title())) {
            return ScrapedMetadata.empty();
        }

        var hasKnownArtist = known(request.artist(), "Unknown Artist");
        ReleaseMatch release = null;
        if (hasKnownArtist && (request.needsAlbum() || request.needsArtwork())) {
            release = findRelease(request);
        }
        var lyrics = request.needsLyrics() && hasKnownArtist ? findLyrics(request) : null;
        var artwork = request.needsArtwork() && release != null ? findArtwork(release.id()) : null;
        var needsCandidate = request.needsTitle()
            || request.needsArtist()
            || request.needsAlbum() && release == null
            || request.needsArtwork() && artwork == null
            || request.needsLyrics() && lyrics == null;
        var match = needsCandidate ? findCandidate(request) : null;
        DownloadCandidate candidate = match == null ? null : match.candidate();

        LyricsValue candidateLyrics = null;
        if (lyrics == null && candidate != null && !blank(candidate.lyrics())) {
            candidateLyrics = LyricsValue.embedded(candidate.lyrics());
        }
        if (artwork == null && candidate != null && !blank(candidate.artworkUrl())) {
            artwork = findArtworkUrl(candidate.artworkUrl());
        }

        var album = request.needsAlbum() && release != null
            ? release.title()
            : request.needsAlbum() && candidate != null ? blankToNull(candidate.album()) : null;
        var plainLyrics = lyrics != null
            ? lyrics.plainLyrics()
            : candidateLyrics == null ? null : candidateLyrics.plain();
        var syncedLyrics = lyrics != null
            ? lyrics.syncedLyrics()
            : candidateLyrics == null ? null : candidateLyrics.synced();
        var metadataSource = candidate != null
            ? "musicdl:" + candidate.source()
            : release != null ? "musicbrainz" : null;
        var lyricsSource = lyrics != null
            ? "lrclib"
            : candidateLyrics != null ? "musicdl:" + candidate.source() : null;
        return new ScrapedMetadata(
            request.needsTitle() && candidate != null ? blankToNull(candidate.title()) : null,
            request.needsArtist() && candidate != null ? blankToNull(candidate.artist()) : null,
            album,
            plainLyrics,
            syncedLyrics,
            artwork == null ? null : artwork.data(),
            artwork == null ? null : artwork.mimeType(),
            lyricsSource,
            metadataSource,
            match == null ? release == null ? 0 : 95 : match.confidence()
        );
    }

    private MetadataCandidateMatcher.Match findCandidate(ScrapeRequest request) {
        if (!downloaderGateway.isEnabled()) {
            return null;
        }
        try {
            var query = known(request.artist(), "Unknown Artist")
                ? request.title() + " " + request.artist()
                : request.title();
            return MetadataCandidateMatcher.best(request, downloaderGateway.search(query))
                .orElse(null);
        } catch (Exception exception) {
            LOGGER.debug(
                "Multi-source metadata lookup failed for {} - {}: {}",
                request.artist(),
                request.title(),
                exception.getMessage()
            );
            return null;
        }
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
        return findArtworkUri(URI.create("https://coverartarchive.org/release/" + releaseId + "/front-500"));
    }

    private ArtworkResponse findArtworkUrl(String rawUrl) {
        try {
            var uri = URI.create(rawUrl);
            if (!"https".equalsIgnoreCase(uri.getScheme()) || blank(uri.getHost())) {
                return null;
            }
            return findArtworkUri(uri);
        } catch (Exception exception) {
            LOGGER.debug("Candidate artwork URL is invalid: {}", exception.getMessage());
            return null;
        }
    }

    private ArtworkResponse findArtworkUri(URI uri) {
        try {
            var request = HttpRequest.newBuilder(uri)
                .timeout(Duration.ofSeconds(15))
                .header("User-Agent", USER_AGENT)
                .GET()
                .build();
            var response = imageClient.send(request, HttpResponse.BodyHandlers.ofByteArray());
            if (response.statusCode() < 200
                || response.statusCode() >= 300
                || response.body().length == 0
                || response.body().length > 10 * 1024 * 1024) {
                return null;
            }
            var mimeType = response.headers().firstValue("Content-Type").orElse("image/jpeg").split(";", 2)[0];
            if (!mimeType.startsWith("image/")) {
                return null;
            }
            return new ArtworkResponse(response.body(), mimeType);
        } catch (Exception exception) {
            LOGGER.debug("Artwork lookup failed for {}: {}", uri, exception.getMessage());
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

    private String blankToNull(String value) {
        return blank(value) ? null : value.strip();
    }

    private boolean known(String value, String placeholder) {
        return !blank(value) && !placeholder.equalsIgnoreCase(value);
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
