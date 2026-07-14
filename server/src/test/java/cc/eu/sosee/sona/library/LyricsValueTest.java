package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class LyricsValueTest {

    @Test
    void recognizesSynchronizedLyrics() {
        var lyrics = LyricsValue.embedded("[00:01.23]第一句\n[00:05.00]第二句");

        assertThat(lyrics.synced()).contains("[00:01.23]第一句");
        assertThat(lyrics.plain()).isNull();
        assertThat(lyrics.source()).isEqualTo("EMBEDDED");
    }

    @Test
    void sidecarAddsTimelineToPlainEmbeddedLyrics() {
        var lyrics = LyricsValue.embedded("第一句\n第二句")
            .withSidecar("[00:01.23]第一句\n[00:05.00]第二句");

        assertThat(lyrics.plain()).isEqualTo("第一句\n第二句");
        assertThat(lyrics.synced()).contains("[00:05.00]第二句");
        assertThat(lyrics.source()).isEqualTo("SIDECAR");
    }
}

