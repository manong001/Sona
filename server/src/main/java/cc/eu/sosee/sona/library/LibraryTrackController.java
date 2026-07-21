package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.config.SonaProperties;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@RestController
@RequestMapping("/api/v1/library/tracks")
class LibraryTrackController {

    private static final Set<String> POOL_TYPES = Set.of("NORMAL", "DISCOVERY");
    private static final Set<String> AUDIENCE_TYPES = Set.of("GENERAL", "CHILD");
    private static final Set<String> REGIONS = Set.of("CN", "KR", "US", "JP", "OTHER");

    private final TrackStore trackStore;
    private final ScanCoordinator scanCoordinator;
    private final TrackAiService trackAiService;
    private final DuplicateTrackService duplicateTrackService;
    private final Path uploadDirectory;

    LibraryTrackController(
        TrackStore trackStore, ScanCoordinator scanCoordinator, SonaProperties properties,
        TrackAiService trackAiService, DuplicateTrackService duplicateTrackService
    ) {
        this.trackStore = trackStore;
        this.scanCoordinator = scanCoordinator;
        this.trackAiService = trackAiService;
        this.duplicateTrackService = duplicateTrackService;
        this.uploadDirectory = properties.getMusicDir().toAbsolutePath().normalize().resolve("Uploads");
    }

    @GetMapping
    List<TrackResponse> tracks(@RequestParam(required = false) String poolType) {
        if (poolType != null && !poolType.isBlank() && !POOL_TYPES.contains(poolType)) {
            throw new ResponseStatusException(BAD_REQUEST, "Invalid pool type");
        }
        return trackStore.findManaged(poolType).stream().map(TrackResponse::from).toList();
    }

    @GetMapping("/duplicates")
    List<DuplicateTrackService.DuplicateTrackGroup> duplicates() {
        return duplicateTrackService.findDuplicates();
    }

    @PatchMapping("/{id}")
    TrackResponse classify(@PathVariable String id, @Valid @RequestBody ClassificationRequest request) {
        if (!POOL_TYPES.contains(request.poolType()) || !AUDIENCE_TYPES.contains(request.audienceType())) {
            throw new ResponseStatusException(BAD_REQUEST, "Invalid classification");
        }
        var genre = normalizedGenre(request.genre());
        if (request.region() != null && !REGIONS.contains(request.region())) {
            throw new ResponseStatusException(BAD_REQUEST, "Invalid region");
        }
        if (!trackStore.classify(
            id, request.poolType(), request.audienceType(), genre, request.region()
        )) {
            throw new ResponseStatusException(NOT_FOUND, "Track not found");
        }
        return TrackResponse.from(trackStore.findById(id).orElseThrow());
    }

    @PatchMapping("/{id}/metadata")
    TrackResponse editMetadata(
        @PathVariable String id, @Valid @RequestBody MetadataEditRequest request
    ) {
        var title = request.title().strip();
        var artist = request.artist().strip();
        var album = request.album().strip();
        var genre = request.genre().strip();
        var relatedGenres = normalizedRelatedGenres(request.relatedGenres(), genre);
        if (!trackStore.editMetadata(
            id, title, artist, album, request.trackNumber(), genre, relatedGenres
        )) {
            throw new ResponseStatusException(NOT_FOUND, "Track not found");
        }
        return TrackResponse.from(trackStore.findById(id).orElseThrow());
    }

    @PostMapping("/{id}/ai-analysis")
    TrackAiService.AiTrackAnalysis analyzeMetadata(@PathVariable String id) {
        return trackAiService.analyze(id);
    }

    @PostMapping("/{id}/rescrape")
    ResponseEntity<ScanStatus> rescrape(@PathVariable String id) {
        var track = trackStore.findById(id)
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Track not found"));
        trackStore.resetMetadata(id);
        return ResponseEntity.accepted().body(scanCoordinator.start(
            uploadDirectory.getParent().relativize(track.path().getParent()).toString()
        ));
    }

    @DeleteMapping("/{id}")
    ResponseEntity<Void> delete(@PathVariable String id) throws IOException {
        var track = trackStore.findById(id)
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Track not found"));
        Files.deleteIfExists(track.path());
        if (track.artworkPath() != null) {
            Files.deleteIfExists(track.artworkPath());
        }
        trackStore.delete(id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping(path = "/upload", consumes = "multipart/form-data")
    ResponseEntity<Void> upload(@RequestPart("files") List<MultipartFile> files) throws IOException {
        if (files.isEmpty()) {
            throw new ResponseStatusException(BAD_REQUEST, "No files supplied");
        }
        Files.createDirectories(uploadDirectory);
        for (var file : files) {
            var original = Path.of(file.getOriginalFilename() == null ? "track" : file.getOriginalFilename())
                .getFileName().toString();
            var target = uploadDirectory.resolve(UUID.randomUUID() + "-" + original).normalize();
            if (!target.startsWith(uploadDirectory)) {
                throw new ResponseStatusException(BAD_REQUEST, "Invalid filename");
            }
            try (var input = file.getInputStream()) {
                Files.copy(input, target, StandardCopyOption.REPLACE_EXISTING);
            }
        }
        scanCoordinator.trigger();
        return ResponseEntity.accepted().build();
    }

    private String normalizedGenre(String genre) {
        if (genre == null) {
            return null;
        }
        var normalized = genre.strip();
        if (normalized.isEmpty() || normalized.length() > 40) {
            throw new ResponseStatusException(BAD_REQUEST, "Invalid genre");
        }
        return normalized;
    }

    private List<String> normalizedRelatedGenres(List<String> genres, String primaryGenre) {
        if (genres == null) {
            return null;
        }
        var normalized = new LinkedHashSet<String>();
        for (var value : genres) {
            if (value == null) {
                continue;
            }
            var genre = value.strip();
            if (genre.isEmpty() || genre.length() > 40) {
                throw new ResponseStatusException(BAD_REQUEST, "Invalid related genre");
            }
            if (!genre.equals(primaryGenre)) {
                normalized.add(genre);
            }
            if (normalized.size() > 5) {
                throw new ResponseStatusException(BAD_REQUEST, "Too many related genres");
            }
        }
        return List.copyOf(normalized);
    }

    record ClassificationRequest(
        @NotBlank String poolType,
        @NotBlank String audienceType,
        String genre,
        String region
    ) {
    }
    record MetadataEditRequest(
        @NotBlank @jakarta.validation.constraints.Size(max = 200) String title,
        @NotBlank @jakarta.validation.constraints.Size(max = 200) String artist,
        @NotBlank @jakarta.validation.constraints.Size(max = 200) String album,
        @jakarta.validation.constraints.PositiveOrZero Integer trackNumber,
        @NotBlank @jakarta.validation.constraints.Size(max = 40) String genre,
        List<String> relatedGenres
    ) {
    }
}
