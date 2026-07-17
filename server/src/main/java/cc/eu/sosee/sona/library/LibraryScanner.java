package cc.eu.sosee.sona.library;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.BasicFileAttributes;
import java.time.Clock;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Stream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
class LibraryScanner {

    private static final Logger LOGGER = LoggerFactory.getLogger(LibraryScanner.class);
    private static final Set<String> SUPPORTED_EXTENSIONS = Set.of(
        "mp3", "m4a", "aac", "flac", "alac", "wav", "aiff", "aif",
        "ogg", "oga", "opus", "ape", "wv", "tta"
    );

    private final ServerMusicDirectoryService directoryService;
    private final TrackStore trackStore;
    private final AudioMetadataExtractor metadataExtractor;
    private final ArtworkStore artworkStore;
    private final MetadataScraper metadataScraper;
    private final FileNameParser fileNameParser;
    private final Clock clock;
    private final AtomicReference<List<String>> lastErrors = new AtomicReference<>(List.of());

    LibraryScanner(
        ServerMusicDirectoryService directoryService,
        TrackStore trackStore,
        AudioMetadataExtractor metadataExtractor,
        ArtworkStore artworkStore,
        MetadataScraper metadataScraper,
        Clock clock
    ) {
        this.directoryService = directoryService;
        this.trackStore = trackStore;
        this.metadataExtractor = metadataExtractor;
        this.artworkStore = artworkStore;
        this.metadataScraper = metadataScraper;
        this.fileNameParser = new FileNameParser();
        this.clock = clock;
    }

    ScanResult scan() throws IOException {
        return scan("");
    }

    ScanResult scan(String relativeDirectory) throws IOException {
        var scanDirectory = directoryService.resolve(relativeDirectory);
        var counts = new int[5];
        var errors = new ArrayList<String>();
        try (Stream<Path> paths = Files.walk(scanDirectory)) {
            paths.filter(Files::isRegularFile)
                .filter(this::isSupported)
                .sorted()
                .forEach(path -> scanFile(path, counts, errors));
        }
        if (relativeDirectory == null || relativeDirectory.isBlank()) {
            counts[2] += removeMissingTracks(scanDirectory);
        }
        lastErrors.set(List.copyOf(errors));
        return new ScanResult(counts[0], counts[1], counts[2], counts[3], counts[4]);
    }

    List<String> lastErrors() {
        return lastErrors.get();
    }

    int removeMissingTracks() {
        return removeMissingTracks(directoryService.resolve(""));
    }

    private int removeMissingTracks(Path directory) {
        var removed = 0;
        for (var track : trackStore.findUnderPath(directory)) {
            if (!Files.isRegularFile(track.path())) {
                trackStore.delete(track.id());
                removed++;
            }
        }
        return removed;
    }

    private void scanFile(Path path, int[] counts, List<String> errors) {
        counts[0]++;
        try {
            var attributes = Files.readAttributes(path, BasicFileAttributes.class);
            var normalizedPath = path.toAbsolutePath().normalize();
            var existing = trackStore.findByPath(normalizedPath);
            if (existing.isPresent()
                && existing.get().fileSize() == attributes.size()
                && existing.get().modifiedAt() == attributes.lastModifiedTime().toMillis()
                && !needsScrapeRetry(existing.get())) {
                counts[3]++;
                return;
            }

            var metadata = metadataExtractor.extract(normalizedPath);
            var parsed = fileNameParser.parse(normalizedPath);
            var retry = existing.filter(
                track -> "NEEDS_REVIEW".equals(track.metadataStatus()) && track.updatedAt() == 0
            );
            var titleHint = retry.map(TrackRecord::title).orElse("");
            var artistHint = retry.map(TrackRecord::artist).orElse("");
            var albumHint = retry.map(TrackRecord::album).orElse("");
            var titleFromTag = hasText(titleHint) || hasText(metadata.title());
            var artistFromTag = hasText(artistHint) || hasText(metadata.artist());
            var title = fileNameParser.stripTrackNumberPrefix(
                firstText(titleHint, metadata.title(), parsed.title(), "Unknown Title")
            );
            var artist = firstText(artistHint, metadata.artist(), parsed.artist(), "Unknown Artist");
            var album = firstText(albumHint, metadata.album(), "Unknown Album");
            var trackNumber = retry.map(TrackRecord::trackNumber).orElseGet(
                () -> metadata.trackNumber() != null ? metadata.trackNumber() : parsed.trackNumber()
            );
            var id = existing.map(TrackRecord::id).orElseGet(() -> UUID.randomUUID().toString());
            var artworkPath = existing.map(TrackRecord::artworkPath).orElse(null);
            if (artworkPath == null && metadata.artwork() != null) {
                artworkPath = artworkStore.save(id, metadata.artwork(), metadata.artworkMimeType());
            }

            var lyrics = LyricsValue.embedded(metadata.lyrics())
                .withSidecar(readSidecarLyrics(normalizedPath));
            var scraped = metadataScraper.scrape(new ScrapeRequest(
                title,
                artist,
                album,
                metadata.durationMs(),
                !titleFromTag,
                !artistFromTag,
                "Unknown Album".equals(album),
                artworkPath == null,
                lyrics.plain() == null && lyrics.synced() == null
            ));
            if (!titleFromTag && hasText(scraped.title())) {
                title = fileNameParser.stripTrackNumberPrefix(scraped.title());
            }
            if (!artistFromTag && hasText(scraped.artist())) {
                artist = scraped.artist().strip();
            }
            if ("Unknown Album".equals(album) && hasText(scraped.album())) {
                album = scraped.album().strip();
            }
            if (lyrics.plain() == null && lyrics.synced() == null) {
                lyrics = new LyricsValue(
                    blankToNull(scraped.plainLyrics()),
                    blankToNull(scraped.syncedLyrics()),
                    hasText(scraped.plainLyrics()) || hasText(scraped.syncedLyrics())
                        ? firstText(scraped.lyricsSource(), "remote")
                        : null
                );
            }
            if (artworkPath == null && scraped.artwork() != null) {
                artworkPath = artworkStore.save(id, scraped.artwork(), scraped.artworkMimeType());
            }
            var now = clock.millis();
            var track = new TrackRecord(
                id,
                normalizedPath,
                attributes.size(),
                attributes.lastModifiedTime().toMillis(),
                title,
                TextNormalizer.sortKey(title),
                artist,
                album,
                trackNumber,
                metadata.durationMs(),
                firstText(metadata.codec(), extension(normalizedPath).toUpperCase(Locale.ROOT)),
                metadata.sampleRate(),
                metadata.bitDepth(),
                artworkPath,
                lyrics.plain(),
                lyrics.synced(),
                lyrics.source(),
                scraped.hasValues() ? "SCRAPED" : titleFromTag && artistFromTag ? "LOCAL" : "NEEDS_REVIEW",
                existing.map(TrackRecord::manualEdited).orElse(false),
                existing.map(TrackRecord::createdAt).orElse(now),
                now,
                existing.map(TrackRecord::poolType).orElse("NORMAL"),
                existing.map(TrackRecord::audienceType).orElse("GENERAL"),
                firstText(existing.map(TrackRecord::genre).orElse(""), metadata.genre(), "未分类"),
                existing.map(TrackRecord::region).orElse("OTHER")
            );
            trackStore.save(track);
            if (existing.isPresent()) {
                counts[2]++;
            } else {
                counts[1]++;
            }
        } catch (Exception exception) {
            counts[4]++;
            if (errors.size() < 50) {
                errors.add(path.getFileName() + "：" + firstText(
                    exception.getMessage(), exception.getClass().getSimpleName()
                ));
            }
            LOGGER.warn("Failed to scan {}: {}", path, exception.getMessage());
        }
    }

    private String readSidecarLyrics(Path audioPath) throws IOException {
        var filename = audioPath.getFileName().toString();
        var extensionIndex = filename.lastIndexOf('.');
        var stem = extensionIndex < 0 ? filename : filename.substring(0, extensionIndex);
        var sidecar = audioPath.resolveSibling(stem + ".lrc");
        return Files.isRegularFile(sidecar) ? Files.readString(sidecar, StandardCharsets.UTF_8) : null;
    }

    private boolean isSupported(Path path) {
        return SUPPORTED_EXTENSIONS.contains(extension(path));
    }

    private String extension(Path path) {
        var name = path.getFileName().toString();
        var separator = name.lastIndexOf('.');
        return separator < 0 ? "" : name.substring(separator + 1).toLowerCase(Locale.ROOT);
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }

    private boolean needsScrapeRetry(TrackRecord track) {
        return "NEEDS_REVIEW".equals(track.metadataStatus()) && track.updatedAt() == 0;
    }

    private String blankToNull(String value) {
        return hasText(value) ? value : null;
    }

    private String firstText(String... values) {
        for (var value : values) {
            if (hasText(value)) {
                return value.strip();
            }
        }
        return "";
    }
}
