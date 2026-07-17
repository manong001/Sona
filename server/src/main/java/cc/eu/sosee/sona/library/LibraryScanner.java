package cc.eu.sosee.sona.library;

import java.io.IOException;
import java.nio.charset.Charset;
import java.nio.charset.MalformedInputException;
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
import java.util.function.Consumer;
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
        return scan("", ScrapeMode.STANDARD);
    }

    ScanResult scan(String relativeDirectory) throws IOException {
        return scan(relativeDirectory, ScrapeMode.STANDARD);
    }

    ScanResult scan(String relativeDirectory, ScrapeMode mode) throws IOException {
        return scan(relativeDirectory, mode, result -> { });
    }

    ScanResult scan(String relativeDirectory, Consumer<ScanResult> progress) throws IOException {
        return scan(relativeDirectory, ScrapeMode.STANDARD, progress);
    }

    ScanResult scan(
        String relativeDirectory, ScrapeMode mode, Consumer<ScanResult> progress
    ) throws IOException {
        var scanDirectory = directoryService.resolve(relativeDirectory);
        var counts = new int[5];
        var errors = new ArrayList<String>();
        try (Stream<Path> paths = Files.walk(scanDirectory)) {
            paths.filter(Files::isRegularFile)
                .filter(this::isSupported)
                .sorted()
                .forEach(path -> {
                    counts[0]++;
                    progress.accept(result(counts));
                    scanFile(path, mode, counts, errors);
                    progress.accept(result(counts));
                });
        }
        if (relativeDirectory == null || relativeDirectory.isBlank()) {
            var removed = removeMissingTracks(scanDirectory);
            counts[2] += removed;
            if (removed > 0) {
                progress.accept(result(counts));
            }
        }
        lastErrors.set(List.copyOf(errors));
        return result(counts);
    }

    ScanResult scanTrackIds(
        List<String> trackIds, ScrapeMode mode, Consumer<ScanResult> progress
    ) {
        var counts = new int[5];
        var errors = new ArrayList<String>();
        trackIds.stream().distinct().forEach(trackId -> {
            counts[0]++;
            progress.accept(result(counts));
            var track = trackStore.findById(trackId);
            if (track.isPresent()) {
                scanFile(track.get().path(), mode, counts, errors);
            } else {
                counts[4]++;
                if (errors.size() < 50) {
                    errors.add(trackId + "：歌曲已不存在，已跳过");
                }
            }
            progress.accept(result(counts));
        });
        lastErrors.set(List.copyOf(errors));
        return result(counts);
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

    private void scanFile(Path path, ScrapeMode mode, int[] counts, List<String> errors) {
        try {
            var attributes = Files.readAttributes(path, BasicFileAttributes.class);
            var normalizedPath = path.toAbsolutePath().normalize();
            var existing = trackStore.findByPath(normalizedPath);
            if (existing.isPresent()
                && existing.get().fileSize() == attributes.size()
                && existing.get().modifiedAt() == attributes.lastModifiedTime().toMillis()
                && !needsScrapeRetry(existing.get())
                && !needsTitleNormalization(existing.get())
                && !hasEncodingDamage(existing.get())
                && !shouldRefreshMissing(existing.get(), mode)
                && !shouldOverwrite(existing.get(), mode)) {
                counts[3]++;
                return;
            }

            var metadata = metadataExtractor.extract(normalizedPath);
            var parsed = fileNameParser.parse(normalizedPath);
            var retry = existing.filter(
                track -> "NEEDS_REVIEW".equals(track.metadataStatus()) && track.updatedAt() == 0
            );
            var overwriteExisting = existing.filter(track -> shouldOverwrite(track, mode));
            var refreshExisting = existing.filter(track -> mode != ScrapeMode.STANDARD
                && (!track.manualEdited() || mode == ScrapeMode.FORCE_OVERWRITE));
            var hintTrack = refreshExisting.or(() -> retry);
            var titleHint = hintTrack.map(TrackRecord::title)
                .filter(value -> !hasEncodingDamage(value)).orElse("");
            var artistHint = hintTrack.map(TrackRecord::artist)
                .filter(value -> !hasEncodingDamage(value)).orElse("");
            var albumHint = hintTrack.map(TrackRecord::album)
                .filter(value -> !hasEncodingDamage(value)).orElse("");
            var titleFromTag = hasText(titleHint) || hasText(metadata.title());
            var artistFromTag = hasText(artistHint) || hasText(metadata.artist());
            var title = fileNameParser.stripTrackNumberPrefix(
                firstText(titleHint, metadata.title(), parsed.title(), "Unknown Title")
            );
            var artist = firstText(artistHint, metadata.artist(), parsed.artist(), "Unknown Artist");
            var album = firstText(albumHint, metadata.album(), "Unknown Album");
            var trackNumber = refreshExisting.or(() -> retry).map(TrackRecord::trackNumber).orElseGet(
                () -> metadata.trackNumber() != null ? metadata.trackNumber() : parsed.trackNumber()
            );
            var id = existing.map(TrackRecord::id).orElseGet(() -> UUID.randomUUID().toString());
            var artworkPath = existing.map(TrackRecord::artworkPath).orElse(null);
            var artworkSource = existing.map(TrackRecord::artworkSource).orElse(null);
            if (artworkPath == null && metadata.artwork() != null) {
                artworkPath = artworkStore.save(id, metadata.artwork(), metadata.artworkMimeType());
                artworkSource = "LOCAL";
            }

            var lyrics = LyricsValue.embedded(metadata.lyrics())
                .withSidecar(readSidecarLyrics(normalizedPath));
            var refreshMissing = mode == ScrapeMode.MISSING_ONLY && refreshExisting.isPresent();
            var needsTitle = overwriteExisting.isPresent()
                || (refreshMissing ? missing(title, "Unknown Title") : !titleFromTag);
            var needsArtist = overwriteExisting.isPresent()
                || (refreshMissing ? missing(artist, "Unknown Artist") : !artistFromTag);
            var needsAlbum = overwriteExisting.isPresent()
                || (refreshMissing ? missing(album, "Unknown Album") : "Unknown Album".equals(album));
            var needsArtwork = overwriteExisting.isPresent() || artworkPath == null;
            var needsLyrics = overwriteExisting.isPresent()
                || (refreshMissing
                    ? refreshExisting.get().plainLyrics() == null
                        && refreshExisting.get().syncedLyrics() == null
                    : lyrics.plain() == null && lyrics.synced() == null);
            var scraped = metadataScraper.scrape(new ScrapeRequest(
                title,
                artist,
                album,
                metadata.durationMs(),
                needsTitle,
                needsArtist,
                needsAlbum,
                needsArtwork,
                needsLyrics
            ));
            if (needsTitle && hasText(scraped.title())) {
                title = fileNameParser.stripTrackNumberPrefix(scraped.title());
            }
            if (needsArtist && hasText(scraped.artist())) {
                artist = scraped.artist().strip();
            }
            if (needsAlbum && hasText(scraped.album())) {
                album = scraped.album().strip();
            }
            if (needsLyrics) {
                var existingTrack = refreshExisting.orElse(null);
                var scrapedPlain = blankToNull(scraped.plainLyrics());
                var scrapedSynced = blankToNull(scraped.syncedLyrics());
                lyrics = new LyricsValue(
                    scrapedPlain != null ? scrapedPlain
                        : existingTrack == null ? null : existingTrack.plainLyrics(),
                    scrapedSynced != null ? scrapedSynced
                        : existingTrack == null ? null : existingTrack.syncedLyrics(),
                    scrapedPlain != null || scrapedSynced != null
                        ? firstText(scraped.lyricsSource(), "remote")
                        : existingTrack == null ? null : existingTrack.lyricsSource()
                );
            }
            if (scraped.artwork() != null) {
                artworkPath = artworkStore.save(id, scraped.artwork(), scraped.artworkMimeType());
                artworkSource = "SCRAPED";
            }
            var forcedIdentity = mode == ScrapeMode.FORCE_OVERWRITE
                && (hasText(scraped.title()) || hasText(scraped.artist()) || hasText(scraped.album()));
            var manualEdited = existing.map(TrackRecord::manualEdited).orElse(false)
                && !forcedIdentity;
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
                manualEdited ? "MANUAL"
                    : scraped.hasValues() ? "SCRAPED" : refreshExisting.map(TrackRecord::metadataStatus)
                        .orElse(titleFromTag && artistFromTag ? "LOCAL" : "NEEDS_REVIEW"),
                manualEdited,
                existing.map(TrackRecord::createdAt).orElse(now),
                now,
                existing.map(TrackRecord::poolType).orElse("NORMAL"),
                existing.map(TrackRecord::audienceType).orElse("GENERAL"),
                firstText(
                    existing.map(TrackRecord::genre)
                        .filter(value -> !hasEncodingDamage(value)).orElse(""),
                    metadata.genre(),
                    "未分类"
                ),
                existing.map(TrackRecord::region).orElse("OTHER"),
                existing.map(TrackRecord::relatedGenres).orElse(List.of()),
                artworkSource
            );
            trackStore.save(
                track, overwriteExisting.isPresent(), mode == ScrapeMode.FORCE_OVERWRITE
            );
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

    private ScanResult result(int[] counts) {
        return new ScanResult(counts[0], counts[1], counts[2], counts[3], counts[4]);
    }

    private String readSidecarLyrics(Path audioPath) throws IOException {
        var filename = audioPath.getFileName().toString();
        var extensionIndex = filename.lastIndexOf('.');
        var stem = extensionIndex < 0 ? filename : filename.substring(0, extensionIndex);
        var sidecar = audioPath.resolveSibling(stem + ".lrc");
        if (!Files.isRegularFile(sidecar)) {
            return null;
        }
        try {
            return Files.readString(sidecar, StandardCharsets.UTF_8);
        } catch (MalformedInputException exception) {
            try {
                return Files.readString(sidecar, Charset.forName("GB18030"));
            } catch (MalformedInputException fallbackException) {
                LOGGER.warn("Ignoring unreadable sidecar lyrics {}", sidecar);
                return null;
            }
        }
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

    private boolean needsTitleNormalization(TrackRecord track) {
        return !track.manualEdited()
            && !fileNameParser.stripTrackNumberPrefix(track.title()).equals(track.title());
    }

    private boolean hasEncodingDamage(TrackRecord track) {
        return !track.manualEdited()
            && (hasEncodingDamage(track.title())
                || hasEncodingDamage(track.artist())
                || hasEncodingDamage(track.album())
                || hasEncodingDamage(track.genre()));
    }

    private boolean hasEncodingDamage(String value) {
        return value != null && value.indexOf('\ufffd') >= 0;
    }

    private boolean shouldOverwrite(TrackRecord track, ScrapeMode mode) {
        return mode == ScrapeMode.FORCE_OVERWRITE
            || mode == ScrapeMode.OVERWRITE && !track.manualEdited();
    }

    private boolean shouldRefreshMissing(TrackRecord track, ScrapeMode mode) {
        return mode == ScrapeMode.MISSING_ONLY
            && !track.manualEdited()
            && (missing(track.title(), "Unknown Title")
                || missing(track.artist(), "Unknown Artist")
                || missing(track.album(), "Unknown Album")
                || track.artworkPath() == null
                || track.plainLyrics() == null && track.syncedLyrics() == null);
    }

    private boolean missing(String value, String placeholder) {
        return !hasText(value) || placeholder.equals(value);
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
