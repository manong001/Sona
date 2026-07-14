package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Path;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

class FileNameParserTest {

    private final FileNameParser parser = new FileNameParser();

    @ParameterizedTest
    @CsvSource(nullValues = "NULL", value = {
        "'01. 邓紫棋 - All About U.flac', '邓紫棋', 'All About U', 1",
        "'03. Thank You.m4a', '', 'Thank You', 3",
        "'宋冬野 - 郭源潮.mp3', '宋冬野', '郭源潮', NULL"
    })
    void parsesSupportedFileNames(String filename, String artist, String title, Integer trackNumber) {
        var result = parser.parse(Path.of(filename));

        assertThat(result.artist()).isEqualTo(artist);
        assertThat(result.title()).isEqualTo(title);
        assertThat(result.trackNumber()).isEqualTo(trackNumber);
    }
}
