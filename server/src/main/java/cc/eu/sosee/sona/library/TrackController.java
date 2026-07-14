package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.config.SonaProperties;
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

    private static final Map<String, MediaType> AUDIO_TYPES = Map.of(
        "mp3", MediaType.parseMediaType("audio/mpeg"),
        "m4a", MediaType.parseMediaType("audio/mp4"),
        "aac", MediaType.parseMediaType("audio/aac"),
        "flac", MediaType.parseMediaType("audio/flac"),
        "alac", MediaType.parseMediaType("audio/mp4"),
        "wav", MediaType.parseMediaType("audio/wav"),
        "aiff", MediaType.parseMediaType("audio/aiff"),
        "aif", MediaType.parseMediaType("audio/aiff")
    );

    private final TrackStore trackStore;
    private final Path musicDirectory;
    private final Path dataDirectory;

    TrackController(TrackStore trackStore, SonaProperties properties) {
        this.trackStore = trackStore;
        this.musicDirectory = properties.getMusicDir().toAbsolutePath().normalize();
        this.dataDirectory = properties.getDataDir().toAbsolutePath().normalize();
    }

    @GetMapping
    TrackPageResponse list(
        @RequestParam(required = false) String q,
        @RequestParam(required = false) String cursor,
        @RequestParam(defaultValue = "50") int limit
    ) {
        var safeLimit = Math.max(1, Math.min(limit, 100));
        var page = trackStore.findPage(q, cursor, safeLimit);
        return new TrackPageResponse(
            page.items().stream().map(TrackResponse::from).toList(),
            page.nextCursor()
        );
    }

    @GetMapping("/{id}")
    TrackResponse get(@PathVariable String id) {
        return TrackResponse.from(findTrack(id));
    }

    @GetMapping("/{id}/stream")
    ResponseEntity<Resource> stream(@PathVariable String id) throws IOException {
        var track = findTrack(id);
        var audioPath = checkedPath(track.path(), musicDirectory);
        return ResponseEntity.ok()
            .header(HttpHeaders.ACCEPT_RANGES, "bytes")
            .contentType(contentType(audioPath))
            .contentLength(Files.size(audioPath))
            .body(new FileSystemResource(audioPath));
    }

    @GetMapping("/{id}/artwork")
    ResponseEntity<Resource> artwork(@PathVariable String id) throws IOException {
        var track = findTrack(id);
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
    LyricsResponse lyrics(@PathVariable String id) {
        var track = findTrack(id);
        if (track.plainLyrics() == null && track.syncedLyrics() == null) {
            throw new ResponseStatusException(NOT_FOUND, "Lyrics not found");
        }
        return new LyricsResponse(track.plainLyrics(), track.syncedLyrics(), track.lyricsSource());
    }

    private TrackRecord findTrack(String id) {
        return trackStore.findById(id)
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

