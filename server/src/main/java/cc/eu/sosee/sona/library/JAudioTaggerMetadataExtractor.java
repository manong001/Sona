package cc.eu.sosee.sona.library;

import java.nio.file.Path;
import org.jaudiotagger.audio.AudioFileIO;
import org.jaudiotagger.tag.FieldKey;
import org.jaudiotagger.tag.Tag;
import org.springframework.stereotype.Component;

@Component
class JAudioTaggerMetadataExtractor implements AudioMetadataExtractor {

    @Override
    public AudioMetadata extract(Path path) throws Exception {
        var audioFile = AudioFileIO.read(path.toFile());
        var header = audioFile.getAudioHeader();
        var tag = audioFile.getTag();
        var artwork = tag == null ? null : tag.getFirstArtwork();

        return new AudioMetadata(
            first(tag, FieldKey.TITLE),
            first(tag, FieldKey.ARTIST),
            first(tag, FieldKey.ALBUM),
            integer(first(tag, FieldKey.TRACK)),
            Math.round(header.getPreciseTrackLength() * 1_000),
            header.getEncodingType(),
            header.getSampleRateAsNumber(),
            header.getBitsPerSample(),
            artwork == null ? null : artwork.getBinaryData(),
            artwork == null ? null : artwork.getMimeType(),
            first(tag, FieldKey.LYRICS)
        );
    }

    private String first(Tag tag, FieldKey fieldKey) {
        if (tag == null) {
            return "";
        }
        var value = tag.getFirst(fieldKey);
        return value == null ? "" : value.trim();
    }

    private Integer integer(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        var separator = value.indexOf('/');
        var firstPart = separator < 0 ? value : value.substring(0, separator);
        try {
            return Integer.valueOf(firstPart.trim());
        } catch (NumberFormatException exception) {
            return null;
        }
    }
}
