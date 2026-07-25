package cc.eu.sosee.sona.download;

import java.nio.file.Path;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

final class LibraryTrackIdentityMatcher {

    private static final long MAX_DURATION_DIFFERENCE_MS = 5_000;
    private static final Pattern DOWNLOAD_TOKEN_SUFFIX = Pattern.compile(
        "\\s+-\\s+[\\p{Alnum}]{8,}(?:\\s+\\(\\d+\\))?\\s*$"
    );

    private LibraryTrackIdentityMatcher() {
    }

    static boolean matches(DownloadCandidate candidate, StoredTrack track) {
        if (candidate.durationMs() == null
            || candidate.durationMs() <= 0
            || track.durationMs() <= 0
            || Math.abs(candidate.durationMs() - track.durationMs())
                > MAX_DURATION_DIFFERENCE_MS
            || !artistsMatch(candidate.artist(), track.artist())) {
            return false;
        }
        if (titlesMatch(candidate.title(), track.title())) {
            return true;
        }
        return filenameTitleAliases(track.path()).stream()
            .anyMatch(alias -> titlesMatch(candidate.title(), alias));
    }

    private static boolean artistsMatch(String source, String local) {
        var sourceArtists = artistSet(source);
        var localArtists = artistSet(local);
        return !sourceArtists.isEmpty() && !localArtists.isEmpty()
            && (sourceArtists.containsAll(localArtists)
                || localArtists.containsAll(sourceArtists));
    }

    private static Set<String> artistSet(String value) {
        var normalized = PlaylistSubscriptionMatcher.normalizedArtists(value);
        return normalized.isEmpty() ? Set.of() : Set.of(normalized.split("/"));
    }

    private static boolean titlesMatch(String source, String local) {
        var sourceTitle = PlaylistSubscriptionMatcher.normalizedText(source);
        var localTitle = PlaylistSubscriptionMatcher.normalizedText(local);
        if (!sourceTitle.isEmpty() && sourceTitle.equals(localTitle)) {
            return true;
        }
        var sourceBase = PlaylistSubscriptionMatcher.normalizedBaseTitle(source);
        var localBase = PlaylistSubscriptionMatcher.normalizedBaseTitle(local);
        return !sourceBase.isEmpty()
            && sourceBase.equals(localBase)
            && !(containsDj(source) && containsDj(local));
    }

    private static ArrayList<String> filenameTitleAliases(String rawPath) {
        var aliases = new ArrayList<String>();
        var filename = Path.of(rawPath).getFileName().toString();
        var extensionIndex = filename.lastIndexOf('.');
        var stem = extensionIndex > 0 ? filename.substring(0, extensionIndex) : filename;
        stem = DOWNLOAD_TOKEN_SUFFIX.matcher(stem).replaceFirst("").strip();
        if (stem.isEmpty()) {
            return aliases;
        }
        aliases.add(stem);
        var artistSeparator = stem.indexOf(" - ");
        if (artistSeparator >= 0 && artistSeparator + 3 < stem.length()) {
            aliases.add(stem.substring(artistSeparator + 3).strip());
        }
        return aliases;
    }

    private static boolean containsDj(String value) {
        return Normalizer.normalize(value == null ? "" : value, Normalizer.Form.NFKC)
            .toLowerCase(Locale.ROOT)
            .contains("dj");
    }

    record StoredTrack(
        String id, String path, String title, String artist, long durationMs
    ) {
    }
}
