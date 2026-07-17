package cc.eu.sosee.sona.library;

import java.nio.file.Path;
import java.util.Locale;
import org.jaudiotagger.audio.AudioFile;
import org.jaudiotagger.audio.AudioFileIO;
import org.jaudiotagger.tag.FieldKey;
import org.jaudiotagger.tag.Tag;
import org.springframework.stereotype.Component;

@Component
class JAudioTaggerMetadataExtractor implements AudioMetadataExtractor {

    @Override
    public AudioMetadata extract(Path path) throws Exception {
        var audioFile = read(path);
        if (audioFile == null) {
            return basicMetadata(path);
        }
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
            first(tag, FieldKey.LYRICS),
            first(tag, FieldKey.GENRE)
        );
    }

    private AudioFile read(Path path) throws Exception {
        try {
            return AudioFileIO.read(path.toFile());
        } catch (NullPointerException exception) {
            if (isMissingMp4ChannelCount(path, exception)) {
                return null;
            }
            throw exception;
        }
    }

    private boolean isMissingMp4ChannelCount(Path path, NullPointerException exception) {
        var filename = path.getFileName().toString().toLowerCase(Locale.ROOT);
        if (!filename.endsWith(".m4a")) {
            return false;
        }
        for (var element : exception.getStackTrace()) {
            if (element.getClassName().equals("org.jaudiotagger.audio.generic.GenericAudioHeader")
                && element.getMethodName().equals("getChannelNumber")) {
                return true;
            }
        }
        return false;
    }

    private AudioMetadata basicMetadata(Path path) {
        var filename = path.getFileName().toString();
        var separator = filename.lastIndexOf('.');
        var codec = separator < 0 ? "" : filename.substring(separator + 1).toUpperCase(Locale.ROOT);
        return new AudioMetadata(
            "", "", "", null, 0, codec, null, null, null, null, "", ""
        );
    }

    private String first(Tag tag, FieldKey fieldKey) {
        if (tag == null) {
            return "";
        }
        try {
            var value = tag.getFirst(fieldKey);
            return value == null ? "" : value.trim();
        } catch (UnsupportedOperationException exception) {
            return "";
        }
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
