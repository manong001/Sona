package cc.eu.sosee.sona.library;

import java.nio.file.Path;
import java.util.regex.Pattern;

final class FileNameParser {

    private static final Pattern TRACK_PREFIX = Pattern.compile(
        "^(\\d{1,3})(?:\\.\\s*|\\s*[-_]\\s*|\\s+)(.+)$"
    );
    private static final Pattern AUDIO_FORMAT_SUFFIX = Pattern.compile(
        "\\s*\\[(?:mp3|m4a|aac|flac|alac|wav|aiff|aif|ogg|oga|opus|ape|wv|tta)\\]\\s*$",
        Pattern.CASE_INSENSITIVE
    );

    String stripTrackNumberPrefix(String title) {
        var stripped = title.strip();
        var matcher = TRACK_PREFIX.matcher(stripped);
        var withoutTrackNumber = matcher.matches() ? matcher.group(2).strip() : stripped;
        return stripAudioFormatSuffix(withoutTrackNumber);
    }

    ParsedFileName parse(Path path) {
        var filename = path.getFileName().toString();
        var extensionIndex = filename.lastIndexOf('.');
        var stem = extensionIndex > 0 ? filename.substring(0, extensionIndex) : filename;

        Integer trackNumber = null;
        var matcher = TRACK_PREFIX.matcher(stem);
        if (matcher.matches()) {
            trackNumber = Integer.parseInt(matcher.group(1));
            stem = matcher.group(2).trim();
        }
        stem = stripAudioFormatSuffix(stem);

        var separatorIndex = stem.indexOf(" - ");
        if (separatorIndex < 0) {
            return new ParsedFileName("", stem.trim(), trackNumber);
        }

        var artist = stem.substring(0, separatorIndex).trim();
        var title = stem.substring(separatorIndex + 3).trim();
        return new ParsedFileName(artist, title, trackNumber);
    }

    private String stripAudioFormatSuffix(String value) {
        return AUDIO_FORMAT_SUFFIX.matcher(value).replaceFirst("").strip();
    }
}
