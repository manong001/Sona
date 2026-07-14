package cc.eu.sosee.sona.library;

import java.nio.file.Path;
import java.util.regex.Pattern;

final class FileNameParser {

    private static final Pattern TRACK_PREFIX = Pattern.compile("^(\\d+)\\.\\s*(.+)$");

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

        var separatorIndex = stem.indexOf(" - ");
        if (separatorIndex < 0) {
            return new ParsedFileName("", stem.trim(), trackNumber);
        }

        var artist = stem.substring(0, separatorIndex).trim();
        var title = stem.substring(separatorIndex + 3).trim();
        return new ParsedFileName(artist, title, trackNumber);
    }
}

