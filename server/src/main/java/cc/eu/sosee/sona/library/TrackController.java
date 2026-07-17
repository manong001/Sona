package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import cc.eu.sosee.sona.config.SonaProperties;
import cc.eu.sosee.sona.download.OnlinePlaybackService;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.NOT_FOUND;

@RestController
@RequestMapping("/api/v1/tracks")
class TrackController {

    private static final Map<String, MediaType> AUDIO_TYPES = Map.ofEntries(
        Map.entry("mp3", MediaType.parseMediaType("audio/mpeg")),
        Map.entry("m4a", MediaType.parseMediaType("audio/mp4")),
        Map.entry("aac", MediaType.parseMediaType("audio/aac")),
        Map.entry("flac", MediaType.parseMediaType("audio/flac")),
        Map.entry("alac", MediaType.parseMediaType("audio/mp4")),
        Map.entry("wav", MediaType.parseMediaType("audio/wav")),
        Map.entry("aiff", MediaType.parseMediaType("audio/aiff")),
        Map.entry("aif", MediaType.parseMediaType("audio/aiff")),
        Map.entry("ogg", MediaType.parseMediaType("audio/ogg")),
        Map.entry("oga", MediaType.parseMediaType("audio/ogg")),
        Map.entry("opus", MediaType.parseMediaType("audio/opus")),
        Map.entry("ape", MediaType.parseMediaType("audio/ape")),
        Map.entry("wv", MediaType.parseMediaType("audio/wavpack")),
        Map.entry("tta", MediaType.parseMediaType("audio/tta"))
    );

    private final TrackStore trackStore;
    private final Path musicDirectory;
    private final Path dataDirectory;
    private final OnlinePlaybackService onlinePlaybackService;

    TrackController(
        TrackStore trackStore, SonaProperties properties, OnlinePlaybackService onlinePlaybackService
    ) {
        this.trackStore = trackStore;
        this.musicDirectory = properties.getMusicDir().toAbsolutePath().normalize();
        this.dataDirectory = properties.getDataDir().toAbsolutePath().normalize();
        this.onlinePlaybackService = onlinePlaybackService;
    }

    @GetMapping
    TrackPageResponse list(
        @AuthenticationPrincipal AuthenticatedUser user,
        @RequestParam(required = false) String q,
        @RequestParam(required = false) String cursor,
        @RequestParam(defaultValue = "50") int limit,
        @RequestParam(defaultValue = "false") boolean childMode,
        @RequestParam(defaultValue = "TITLE") String sort,
        @RequestParam(required = false) String genre,
        @RequestParam(required = false) String codec,
        @RequestParam(required = false) String metadataStatus
    ) {
        var safeLimit = Math.max(1, Math.min(limit, 100));
        var page = trackStore.findPage(
            q, cursor, safeLimit, user.id(), childMode, sort, genre, codec, metadataStatus
        );
        return new TrackPageResponse(
            page.items().stream().map(TrackResponse::from).toList(),
            page.nextCursor()
        );
    }

    @GetMapping("/random")
    List<TrackResponse> random(
        @AuthenticationPrincipal AuthenticatedUser user,
        @RequestParam(defaultValue = "50") int limit,
        @RequestParam(defaultValue = "false") boolean childMode
    ) {
        var safeLimit = Math.max(1, Math.min(limit, 100));
        return trackStore.findRandom(safeLimit, user.id(), childMode).stream().map(TrackResponse::from).toList();
    }

    @GetMapping("/discovery")
    List<TrackResponse> discovery(
        @AuthenticationPrincipal AuthenticatedUser user,
        @RequestParam(defaultValue = "10") int limit,
        @RequestParam(defaultValue = "false") boolean childMode
    ) {
        var safeLimit = Math.max(1, Math.min(limit, 50));
        return trackStore.findDiscovery(safeLimit, user.id(), childMode).stream().map(TrackResponse::from).toList();
    }

    @GetMapping("/{id}")
    TrackResponse get(@AuthenticationPrincipal AuthenticatedUser user, @PathVariable String id) {
        return TrackResponse.from(findTrack(id, user.id()));
    }

    @GetMapping("/{id}/similar")
    List<TrackResponse> similar(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String id,
        @RequestParam(defaultValue = "10") int limit,
        @RequestParam(defaultValue = "false") boolean childMode
    ) {
        var track = findTrack(id, user.id());
        var candidates = trackStore.findSimilarCandidates(id, user.id(), childMode);
        return SimilarTrackService.rank(
            track, track.relatedGenres(), candidates, Math.max(1, Math.min(limit, 50))
        ).stream().map(TrackResponse::from).toList();
    }

    @GetMapping("/{id}/stream")
    ResponseEntity<Resource> stream(
        @AuthenticationPrincipal AuthenticatedUser user, @PathVariable String id
    ) throws IOException {
        var track = findTrack(id, user.id());
        var audioPath = checkedPath(track.path(), musicDirectory);
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCEPT_RANGES, "bytes")
            .contentType(contentType(audioPath))
            .contentLength(Files.size(audioPath))
            .body(new FileSystemResource(audioPath));
    }

    @GetMapping("/{id}/fallback-stream")
    ResponseEntity<Void> fallbackStream(
        @AuthenticationPrincipal AuthenticatedUser user, @PathVariable String id
    ) {
        var track = findTrack(id, user.id());
        var url = onlinePlaybackService.resolve(track.title(), track.artist(), track.durationMs());
        return ResponseEntity.status(302).header(HttpHeaders.LOCATION, url).build();
    }

    @GetMapping("/{id}/artwork")
    ResponseEntity<Resource> artwork(
        @AuthenticationPrincipal AuthenticatedUser user, @PathVariable String id
    ) throws IOException {
        var track = findTrack(id, user.id());
        if (track.artworkPath() == null) {
            throw new ResponseStatusException(NOT_FOUND, "Artwork not found");
        }
        var artworkPath = checkedPath(track.artworkPath(), dataDirectory);
        var contentType = artworkPath.getFileName().toString().endsWith(".png")
            ? MediaType.IMAGE_PNG
            : MediaType.IMAGE_JPEG;
        return ResponseEntity.ok()
            .contentType(contentType)
            .contentLength(Files.size(artworkPath))
            .body(new FileSystemResource(artworkPath));
    }

    @GetMapping("/{id}/lyrics")
    LyricsResponse lyrics(@AuthenticationPrincipal AuthenticatedUser user, @PathVariable String id) {
        var track = findTrack(id, user.id());
        if (track.plainLyrics() == null && track.syncedLyrics() == null) {
            throw new ResponseStatusException(NOT_FOUND, "Lyrics not found");
        }
        return new LyricsResponse(track.plainLyrics(), track.syncedLyrics(), track.lyricsSource());
    }

    private TrackRecord findTrack(String id, String userId) {
        return trackStore.findVisibleById(id, userId)
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Track not found"));
    }

    private Path checkedPath(Path path, Path allowedDirectory) throws IOException {
        var realDirectory = allowedDirectory.toRealPath();
        var realPath = path.toRealPath();
        if (!realPath.startsWith(realDirectory) || !Files.isRegularFile(realPath)) {
            throw new ResponseStatusException(NOT_FOUND, "File not found");
        }
        return realPath;
    }

    private MediaType contentType(Path path) {
        var filename = path.getFileName().toString();
        var separator = filename.lastIndexOf('.');
        var extension = separator < 0 ? "" : filename.substring(separator + 1).toLowerCase();
        return AUDIO_TYPES.getOrDefault(extension, MediaType.APPLICATION_OCTET_STREAM);
    }

    record TrackPageResponse(List<TrackResponse> items, String nextCursor) {
    }

    record LyricsResponse(String plain, String synced, String source) {
    }
}
