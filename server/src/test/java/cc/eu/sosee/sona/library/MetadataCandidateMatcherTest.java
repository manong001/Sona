package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;

import cc.eu.sosee.sona.download.DownloadCandidate;
import java.util.List;
import org.junit.jupiter.api.Test;

class MetadataCandidateMatcherTest {

    @Test
    void selectsExactTitleArtistAndDurationMatch() {
        var request = new ScrapeRequest(
            "All About U",
            "邓紫棋",
            "Unknown Album",
            240_000,
            true,
            true,
            true,
            true,
            true
        );
        var wrongArtist = candidate("All About U", "Other", "Album", 240_000);
        var exact = candidate("All About U", "邓紫棋", "18...", 242_000);

        var match = MetadataCandidateMatcher.best(request, List.of(wrongArtist, exact));

        assertThat(match).isPresent();
        assertThat(match.orElseThrow().candidate()).isEqualTo(exact);
        assertThat(match.orElseThrow().confidence()).isGreaterThanOrEqualTo(90);
    }

    @Test
    void rejectsWrongArtistEvenWhenTitleMatches() {
        var request = new ScrapeRequest(
            "郭源潮",
            "宋冬野",
            "Unknown Album",
            300_000,
            true,
            true,
            true,
            true,
            true
        );

        var match = MetadataCandidateMatcher.best(
            request,
            List.of(candidate("郭源潮", "其他歌手", "郭源潮", 300_000))
        );

        assertThat(match).isEmpty();
    }

    @Test
    void requiresDurationWhenLocalArtistIsUnknown() {
        var request = new ScrapeRequest(
            "Thank You",
            "Unknown Artist",
            "Unknown Album",
            180_000,
            true,
            true,
            true,
            true,
            true
        );

        assertThat(MetadataCandidateMatcher.best(
            request,
            List.of(candidate("Thank You", "Artist", "Album", 181_000))
        )).isPresent();
        assertThat(MetadataCandidateMatcher.best(
            request,
            List.of(candidate("Thank You", "Artist", "Album", 260_000))
        )).isEmpty();
    }

    private DownloadCandidate candidate(String title, String artist, String album, long durationMs) {
        return new DownloadCandidate(
            "candidate-1",
            "NeteaseMusicClient",
            "网易云音乐",
            title,
            artist,
            album,
            "flac",
            "FLAC · 1411 kbps",
            durationMs,
            10_000_000L,
            "https://example.test/cover.jpg",
            true,
            "[00:01.00]歌词"
        );
    }
}
