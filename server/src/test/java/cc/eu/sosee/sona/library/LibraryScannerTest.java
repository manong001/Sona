package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;

import cc.eu.sosee.sona.config.SonaProperties;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.FileTime;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class LibraryScannerTest {

    @TempDir
    Path temporaryDirectory;

    @Test
    void importsThenRetriesUnchangedTrackThatStillNeedsReview() throws Exception {
        var musicDirectory = Files.createDirectories(temporaryDirectory.resolve("music"));
        var audioPath = Files.writeString(musicDirectory.resolve("01. 邓紫棋 - All About U.flac"), "audio");
        var store = new InMemoryTrackStore();
        var scanner = scanner(musicDirectory, store);

        var first = scanner.scan();
        var second = scanner.scan();

        assertThat(first).isEqualTo(new ScanResult(1, 1, 0, 0, 0));
        assertThat(second).isEqualTo(new ScanResult(1, 0, 1, 0, 0));
        var track = store.findByPath(audioPath).orElseThrow();
        assertThat(track.title()).isEqualTo("All About U");
        assertThat(track.artist()).isEqualTo("邓紫棋");
        assertThat(track.trackNumber()).isEqualTo(1);
        assertThat(track.metadataStatus()).isEqualTo("NEEDS_REVIEW");
        assertThat(track.poolType()).isEqualTo("NORMAL");
    }

    @Test
    void updatesChangedTrackWithoutChangingItsId() throws Exception {
        var musicDirectory = Files.createDirectories(temporaryDirectory.resolve("music"));
        var audioPath = Files.writeString(musicDirectory.resolve("宋冬野 - 郭源潮.mp3"), "audio");
        var store = new InMemoryTrackStore();
        var scanner = scanner(musicDirectory, store);
        scanner.scan();
        var originalId = store.findByPath(audioPath).orElseThrow().id();

        Files.writeString(audioPath, "changed audio");
        Files.setLastModifiedTime(audioPath, FileTime.fromMillis(System.currentTimeMillis() + 2_000));
        var result = scanner.scan();

        assertThat(result).isEqualTo(new ScanResult(1, 0, 1, 0, 0));
        assertThat(store.findByPath(audioPath).orElseThrow().id()).isEqualTo(originalId);
    }

    @Test
    void importsOnlyTheSelectedServerDirectory() throws Exception {
        var musicDirectory = Files.createDirectories(temporaryDirectory.resolve("music"));
        var selected = Files.createDirectories(musicDirectory.resolve("华语/林俊杰"));
        var other = Files.createDirectories(musicDirectory.resolve("欧美"));
        var selectedTrack = Files.writeString(selected.resolve("林俊杰 - 江南.mp3"), "audio");
        var otherTrack = Files.writeString(other.resolve("Other - Song.mp3"), "audio");
        var store = new InMemoryTrackStore();

        var result = scanner(musicDirectory, store).scan("华语/林俊杰");

        assertThat(result).isEqualTo(new ScanResult(1, 1, 0, 0, 0));
        assertThat(store.findByPath(selectedTrack)).isPresent();
        assertThat(store.findByPath(otherTrack)).isEmpty();
    }

    @Test
    void keepsLocalIdentityAndFillsMissingMetadataFromScraper() throws Exception {
        var musicDirectory = Files.createDirectories(temporaryDirectory.resolve("music"));
        var audioPath = Files.writeString(musicDirectory.resolve("宋冬野 - 郭源潮.mp3"), "audio");
        var store = new InMemoryTrackStore();
        MetadataScraper scraper = request -> new ScrapedMetadata(
            "郭源潮",
            "plain lyrics",
            "[00:01.00]synced lyrics",
            new byte[] {1, 2, 3},
            "image/jpeg"
        );

        var result = scanner(musicDirectory, store, scraper).scan();

        assertThat(result).isEqualTo(new ScanResult(1, 1, 0, 0, 0));
        var track = store.findByPath(audioPath).orElseThrow();
        assertThat(track.title()).isEqualTo("郭源潮");
        assertThat(track.artist()).isEqualTo("宋冬野");
        assertThat(track.album()).isEqualTo("郭源潮");
        assertThat(track.plainLyrics()).isEqualTo("plain lyrics");
        assertThat(track.syncedLyrics()).isEqualTo("[00:01.00]synced lyrics");
        assertThat(track.artworkPath()).isRegularFile();
        assertThat(track.metadataStatus()).isEqualTo("SCRAPED");
    }

    @Test
    void retriesUnchangedTrackWithoutScrapedDataAndFillsMetadataLater() throws Exception {
        var musicDirectory = Files.createDirectories(temporaryDirectory.resolve("music"));
        var audioPath = Files.writeString(musicDirectory.resolve("测试艺人 - 待补全.mp3"), "audio");
        var attempts = new AtomicInteger();
        MetadataScraper scraper = request -> attempts.incrementAndGet() == 1
            ? ScrapedMetadata.empty()
            : new ScrapedMetadata(
                "补全专辑", null, null, new byte[] {4, 5, 6}, "image/jpeg"
            );
        var store = new InMemoryTrackStore();
        AudioMetadataExtractor extractor = path -> new AudioMetadata(
            "待补全", "测试艺人", "", null, 180_000, "test", 44_100, 16,
            null, null, ""
        );
        var scanner = scanner(musicDirectory, store, scraper, extractor);

        var first = scanner.scan();
        var second = scanner.scan();

        assertThat(first).isEqualTo(new ScanResult(1, 1, 0, 0, 0));
        assertThat(second).isEqualTo(new ScanResult(1, 0, 1, 0, 0));
        var track = store.findByPath(audioPath).orElseThrow();
        assertThat(track.album()).isEqualTo("补全专辑");
        assertThat(track.artworkPath()).isRegularFile();
        assertThat(track.metadataStatus()).isEqualTo("SCRAPED");
        assertThat(attempts).hasValue(2);
    }

    private LibraryScanner scanner(Path musicDirectory, TrackStore store) throws Exception {
        return scanner(musicDirectory, store, request -> ScrapedMetadata.empty());
    }

    private LibraryScanner scanner(
        Path musicDirectory,
        TrackStore store,
        MetadataScraper metadataScraper
    ) throws Exception {
        AudioMetadataExtractor extractor = path -> new AudioMetadata(
            "", "", "", null, 180_000, "test", 44_100, 16, null, null, ""
        );
        return scanner(musicDirectory, store, metadataScraper, extractor);
    }

    private LibraryScanner scanner(
        Path musicDirectory,
        TrackStore store,
        MetadataScraper metadataScraper,
        AudioMetadataExtractor extractor
    ) throws Exception {
        var properties = new SonaProperties();
        properties.setMusicDir(musicDirectory);
        properties.setDataDir(temporaryDirectory.resolve("data"));
        return new LibraryScanner(
            new ServerMusicDirectoryService(properties),
            store,
            extractor,
            new ArtworkStore(properties),
            metadataScraper,
            Clock.fixed(Instant.parse("2026-07-14T00:00:00Z"), ZoneOffset.UTC)
        );
    }

    private static final class InMemoryTrackStore implements TrackStore {

        private final Map<Path, TrackRecord> tracks = new LinkedHashMap<>();

        @Override
        public Optional<TrackRecord> findByPath(Path path) {
            return Optional.ofNullable(tracks.get(path.toAbsolutePath().normalize()));
        }

        @Override
        public Optional<TrackRecord> findById(String id) {
            return tracks.values().stream().filter(track -> track.id().equals(id)).findFirst();
        }

        @Override
        public Optional<TrackRecord> findVisibleById(String id, String userId) {
            return findById(id);
        }

        @Override
        public void save(TrackRecord track) {
            tracks.put(track.path().toAbsolutePath().normalize(), track);
        }

        @Override
        public TrackPageData findPage(
            String query, String cursor, int limit, String userId, boolean childOnly
        ) {
            throw new UnsupportedOperationException();
        }

        @Override
        public java.util.List<TrackRecord> findRandom(int limit, String userId, boolean childOnly) {
            return tracks.values().stream().limit(limit).toList();
        }

        @Override
        public java.util.List<TrackRecord> findDiscovery(int limit, String userId, boolean childOnly) {
            return java.util.List.of();
        }

        @Override
        public java.util.List<TrackRecord> findManaged(String poolType) {
            return tracks.values().stream().toList();
        }

        @Override
        public java.util.List<TrackRecord> findDailyCandidates(
            String userId, boolean childOnly, long recentAfter, int limit
        ) {
            return tracks.values().stream().limit(limit).toList();
        }

        @Override
        public java.util.List<String> findGenres(String userId, boolean childOnly) {
            return java.util.List.of();
        }

        @Override
        public java.util.List<TrackRecord> findByGenre(
            String genre, String userId, boolean childOnly, int limit
        ) {
            return java.util.List.of();
        }

        @Override
        public java.util.List<ChartTrackData> findChart(
            String region, String userId, boolean childOnly, int limit
        ) {
            return java.util.List.of();
        }

        @Override
        public boolean classify(
            String id, String poolType, String audienceType, String genre, String region
        ) {
            return false;
        }

        @Override
        public boolean delete(String id) {
            return false;
        }
    }
}
