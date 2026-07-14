package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;

@EnabledIfSystemProperty(named = "sona.samples", matches = "true")
class JAudioTaggerMetadataExtractorTest {

    private final JAudioTaggerMetadataExtractor extractor = new JAudioTaggerMetadataExtractor();

    @Test
    void readsFlacTagsAndArtwork() throws Exception {
        var metadata = extractor.extract(Path.of(
            "/Users/leeshun/Downloads/01. 邓紫棋 - All About U.flac"
        ));

        assertThat(metadata.title()).isEqualTo("All About U");
        assertThat(metadata.artist()).isEqualTo("邓紫棋");
        assertThat(metadata.codec()).containsIgnoringCase("FLAC");
        assertThat(metadata.durationMs()).isBetween(241_000L, 242_000L);
        assertThat(metadata.artwork()).isNotEmpty();
    }

    @Test
    void readsAlacTagsArtworkAndPlainLyrics() throws Exception {
        var metadata = extractor.extract(Path.of(
            "/Users/leeshun/Downloads/03. Thank You.m4a"
        ));

        assertThat(metadata.title()).isEqualTo("Thank You");
        assertThat(metadata.artist()).isEqualTo("Song Dongye");
        assertThat(metadata.codec()).containsIgnoringCase("ALAC");
        assertThat(metadata.artwork()).isNotEmpty();
        assertThat(metadata.lyrics()).contains("謝謝你");
    }

    @Test
    void readsMp3SynchronizedLyrics() throws Exception {
        var metadata = extractor.extract(Path.of(
            "/Users/leeshun/Downloads/宋冬野 - 郭源潮.mp3"
        ));

        assertThat(metadata.title()).isEqualTo("郭源潮");
        assertThat(metadata.artist()).isEqualTo("宋冬野");
        assertThat(metadata.artwork()).isNotEmpty();
        assertThat(metadata.lyrics()).contains("[00:24.26]");
    }
}

