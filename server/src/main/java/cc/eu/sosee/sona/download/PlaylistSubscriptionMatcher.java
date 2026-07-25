package cc.eu.sosee.sona.download;

import com.github.houbb.opencc4j.util.ZhConverterUtil;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.web.util.HtmlUtils;

@Component
class PlaylistSubscriptionMatcher {

    private static final int MAX_SUGGESTIONS = 3;
    private static final double MIN_TITLE_SIMILARITY = 0.70;
    private static final double MIN_AUTOMATIC_TITLE_SIMILARITY = 0.92;
    private static final double MIN_AUTOMATIC_SCORE_LEAD = 8;
    private static final long MAX_AUTOMATIC_DURATION_DIFFERENCE_MS = 5_000;
    private static final Pattern ARTIST_SEPARATOR = Pattern.compile(
        "(?i)\\s*(?:、|/|,|，|&|＆|;|；|\\bfeat\\.?\\b|\\bft\\.?\\b)\\s*"
    );
    private static final Pattern BRACKETED_CONTENT = Pattern.compile(
        "\\([^()]*\\)|（[^（）]*）|\\[[^\\[\\]]*]|【[^【】]*】"
    );
    private static final Set<String> VERSION_MARKERS = Set.of(
        "live", "remix", "instrumental", "acoustic", "伴奏", "现场", "翻唱", "纯音乐"
    );

    private final JdbcClient jdbcClient;

    PlaylistSubscriptionMatcher(JdbcClient jdbcClient) {
        this.jdbcClient = jdbcClient;
    }

    Session open() {
        var tracks = jdbcClient.sql("""
                SELECT id, path, title, artist, album, duration_ms, codec,
                       sample_rate, bit_depth, file_size
                FROM tracks ORDER BY updated_at DESC, id
                """)
            .query((resultSet, rowNumber) -> new LocalTrack(
                resultSet.getString("id"), resultSet.getString("path"),
                resultSet.getString("title"),
                resultSet.getString("artist"), resultSet.getString("album"),
                resultSet.getLong("duration_ms"), resultSet.getString("codec"),
                (Integer) resultSet.getObject("sample_rate"),
                (Integer) resultSet.getObject("bit_depth"),
                resultSet.getLong("file_size")
            ))
            .list();
        return new Session(tracks);
    }

    static String normalizedText(String value) {
        if (value == null) {
            return "";
        }
        var decoded = HtmlUtils.htmlUnescape(value);
        var normalized = Normalizer.normalize(ZhConverterUtil.toSimple(decoded), Normalizer.Form.NFKC)
            .toLowerCase(Locale.ROOT);
        var result = new StringBuilder(normalized.length());
        normalized.codePoints()
            .filter(Character::isLetterOrDigit)
            .forEach(result::appendCodePoint);
        return result.toString();
    }

    static String normalizedArtists(String value) {
        if (value == null || value.isBlank()) {
            return "";
        }
        return Arrays.stream(ARTIST_SEPARATOR.split(Normalizer.normalize(value, Normalizer.Form.NFKC)))
            .map(PlaylistSubscriptionMatcher::normalizedText)
            .filter(part -> !part.isEmpty())
            .distinct()
            .sorted()
            .reduce((left, right) -> left + "/" + right)
            .orElse("");
    }

    final class Session {

        private final List<LocalTrack> tracks;
        private final Map<String, List<LocalTrack>> normalizedTitles = new HashMap<>();
        private final Map<String, List<LocalTrack>> normalizedBaseTitles = new HashMap<>();
        private final Set<String> trackIds;

        private Session(List<LocalTrack> tracks) {
            this.tracks = tracks.stream().sorted(localQualityComparator()).toList();
            this.trackIds = tracks.stream().map(LocalTrack::trackId).collect(java.util.stream.Collectors.toSet());
            for (var track : this.tracks) {
                normalizedTitles.computeIfAbsent(
                    normalizedText(track.title()), ignored -> new ArrayList<>()
                )
                    .add(track);
                normalizedBaseTitles.computeIfAbsent(
                    normalizedBaseTitle(track.title()), ignored -> new ArrayList<>()
                )
                    .add(track);
            }
        }

        boolean containsTrack(String trackId) {
            return trackId != null && trackIds.contains(trackId);
        }

        MatchResult match(DownloadCandidate candidate) {
            return match(candidate, Set.of(), true);
        }

        MatchResult match(DownloadCandidate candidate, Set<String> excludedTrackIds) {
            return match(candidate, excludedTrackIds, true);
        }

        MatchResult match(
            DownloadCandidate candidate, Set<String> excludedTrackIds, boolean strictMode
        ) {
            var automaticTrack = automaticCandidates(candidate)
                .filter(track -> !excludedTrackIds.contains(track.trackId()))
                .filter(track -> isAutomaticMatch(candidate, track, strictMode)
                    || isMetadataEquivalentMatch(candidate, track, strictMode))
                .findFirst();
            if (automaticTrack.isPresent()) {
                return new MatchResult(Optional.of(automaticTrack.get().trackId()), List.of());
            }
            var rankedTracks = tracks.stream()
                .filter(track -> !excludedTrackIds.contains(track.trackId()))
                .map(track -> score(candidate, track))
                .flatMap(Optional::stream)
                .sorted(Comparator.comparingDouble(ScoredTrack::score).reversed()
                    .thenComparing(value -> value.track().trackId()))
                .limit(MAX_SUGGESTIONS)
                .toList();
            if (!strictMode && isHighConfidenceAutomaticMatch(candidate, rankedTracks)) {
                return new MatchResult(
                    Optional.of(rankedTracks.get(0).track().trackId()), List.of()
                );
            }
            var suggestions = rankedTracks.stream()
                .map(value -> new Suggestion(
                    value.track().trackId(), value.track().title(), value.track().artist(),
                    value.track().album(), value.track().durationMs(),
                    (int) Math.round(value.score())
                ))
                .toList();
            return new MatchResult(Optional.empty(), suggestions);
        }

        Optional<Suggestion> bestStrictMatch(
            DownloadCandidate candidate, Set<String> excludedTrackIds
        ) {
            return bestStrictMatch(candidate, excludedTrackIds, true);
        }

        Optional<Suggestion> bestStrictMatch(
            DownloadCandidate candidate, Set<String> excludedTrackIds, boolean strictMode
        ) {
            var title = normalizedText(candidate.title());
            if (title.isEmpty()) {
                return Optional.empty();
            }
            return automaticCandidates(candidate)
                .filter(track -> !excludedTrackIds.contains(track.trackId()))
                .filter(track -> isAutomaticMatch(candidate, track, strictMode)
                    || isMetadataEquivalentMatch(candidate, track, strictMode))
                .map(track -> new ScoredTrack(track, strictScore(candidate, track)))
                .sorted(Comparator.comparingDouble(ScoredTrack::score).reversed()
                    .thenComparing(value -> value.track().trackId()))
                .findFirst()
                .map(value -> new Suggestion(
                    value.track().trackId(), value.track().title(), value.track().artist(),
                    value.track().album(), value.track().durationMs(),
                    (int) Math.round(value.score())
                ));
        }

        private Stream<LocalTrack> automaticCandidates(DownloadCandidate candidate) {
            return Stream.concat(
                    normalizedTitles.getOrDefault(
                        normalizedText(candidate.title()), List.of()
                    ).stream(),
                    normalizedBaseTitles.getOrDefault(
                        normalizedBaseTitle(candidate.title()), List.of()
                    ).stream()
                )
                .distinct()
                .sorted(localQualityComparator());
        }
    }

    private boolean isHighConfidenceAutomaticMatch(
        DownloadCandidate candidate, List<ScoredTrack> rankedTracks
    ) {
        if (rankedTracks.isEmpty() || candidate.durationMs() == null || candidate.durationMs() <= 0) {
            return false;
        }
        var best = rankedTracks.get(0);
        var track = best.track();
        var sourceArtists = normalizedArtistSet(candidate.artist());
        if (sourceArtists.isEmpty() || !sourceArtists.equals(normalizedArtistSet(track.artist()))) {
            return false;
        }
        var titleSimilarity = similarity(
            normalizedTitleForSimilarity(candidate.title()),
            normalizedTitleForSimilarity(track.title())
        );
        if (titleSimilarity < MIN_AUTOMATIC_TITLE_SIMILARITY
            || track.durationMs() <= 0
            || Math.abs(candidate.durationMs() - track.durationMs())
                > MAX_AUTOMATIC_DURATION_DIFFERENCE_MS
            || hasVersionMismatch(candidate.title(), track.title())) {
            return false;
        }
        return rankedTracks.size() == 1
            || best.score() - rankedTracks.get(1).score() >= MIN_AUTOMATIC_SCORE_LEAD;
    }

    private static boolean isAutomaticMatch(
        DownloadCandidate candidate, LocalTrack track, boolean strictMode
    ) {
        return normalizedText(candidate.title()).equals(normalizedText(track.title()))
            && (artistsMatch(candidate.artist(), track.artist(), strictMode)
                || remoteAddsCollaboratingArtists(candidate, track));
    }

    private static boolean remoteAddsCollaboratingArtists(
        DownloadCandidate candidate, LocalTrack track
    ) {
        var remoteArtists = normalizedArtistSet(candidate.artist());
        var localArtists = normalizedArtistSet(track.artist());
        return candidate.durationMs() != null
            && candidate.durationMs() > 0
            && track.durationMs() > 0
            && Math.abs(candidate.durationMs() - track.durationMs())
                <= MAX_AUTOMATIC_DURATION_DIFFERENCE_MS
            && remoteArtists.size() > localArtists.size()
            && remoteArtists.containsAll(localArtists)
            && !localArtists.isEmpty()
            && normalizedPrimaryArtist(candidate.artist())
                .equals(normalizedPrimaryArtist(track.artist()));
    }

    private static String normalizedPrimaryArtist(String value) {
        if (value == null || value.isBlank()) {
            return "";
        }
        return normalizedText(ARTIST_SEPARATOR.split(
            Normalizer.normalize(value, Normalizer.Form.NFKC), 2
        )[0]);
    }

    private boolean isMetadataEquivalentMatch(
        DownloadCandidate candidate, LocalTrack track, boolean strictMode
    ) {
        if (candidate.durationMs() == null || candidate.durationMs() <= 0
            || track.durationMs() <= 0
            || Math.abs(candidate.durationMs() - track.durationMs())
                > MAX_AUTOMATIC_DURATION_DIFFERENCE_MS) {
            return false;
        }
        var candidateTitle = normalizedBaseTitle(candidate.title());
        return !candidateTitle.isEmpty()
            && candidateTitle.equals(normalizedBaseTitle(track.title()))
            && artistsMatch(candidate.artist(), track.artist(), strictMode)
            && !hasMetadataVersionMismatch(candidate, track);
    }

    private static boolean artistsMatch(String source, String local, boolean strictMode) {
        var sourceArtists = normalizedArtistSet(source);
        var localArtists = normalizedArtistSet(local);
        return !sourceArtists.isEmpty() && (strictMode
            ? localArtists.equals(sourceArtists)
            : localArtists.containsAll(sourceArtists));
    }

    private double strictScore(DownloadCandidate candidate, LocalTrack track) {
        var score = artistOverlap(candidate.artist(), track.artist()) * 100
            + similarity(normalizedText(candidate.album()), normalizedText(track.album())) * 10;
        if (candidate.durationMs() != null && candidate.durationMs() > 0) {
            var difference = Math.abs(candidate.durationMs() - track.durationMs());
            if (difference <= 4_000) {
                score += 5;
            } else if (difference <= 10_000) {
                score += 2;
            }
        }
        return score;
    }

    private Optional<ScoredTrack> score(DownloadCandidate candidate, LocalTrack track) {
        var titleSimilarity = similarity(
            normalizedTitleForSimilarity(candidate.title()), normalizedTitleForSimilarity(track.title())
        );
        if (titleSimilarity < MIN_TITLE_SIMILARITY) {
            return Optional.empty();
        }
        var artistSimilarity = artistOverlap(candidate.artist(), track.artist());
        var albumSimilarity = similarity(
            normalizedText(candidate.album()), normalizedText(track.album())
        );
        var score = titleSimilarity * 100 + artistSimilarity * 15 + albumSimilarity * 5;
        if (candidate.durationMs() != null && candidate.durationMs() > 0) {
            var durationDifference = Math.abs(candidate.durationMs() - track.durationMs());
            if (durationDifference <= 4_000) {
                score += 5;
            } else if (durationDifference <= 10_000) {
                score += 2;
            } else if (durationDifference >= 30_000) {
                score -= 5;
            }
        }
        if (hasVersionMismatch(candidate.title(), track.title())) {
            score -= 15;
        }
        return Optional.of(new ScoredTrack(track, score));
    }

    private boolean hasMetadataVersionMismatch(
        DownloadCandidate candidate, LocalTrack track
    ) {
        var remoteTitle = normalizedVersionText(candidate.title());
        var remoteAlbum = normalizedVersionText(candidate.album());
        var localTitle = normalizedVersionText(track.title());
        var localAlbum = normalizedVersionText(track.album());
        var localFileName = normalizedVersionText(fileName(track.path()));
        return VERSION_MARKERS.stream().anyMatch(marker ->
            (hasMarker(remoteTitle, marker) || hasMarker(remoteAlbum, marker))
                != (hasMarker(localTitle, marker) || hasMarker(localAlbum, marker)
                    || hasMarker(localFileName, marker))
        );
    }

    private boolean hasVersionMismatch(String remoteTitle, String localTitle) {
        var remote = normalizedVersionText(remoteTitle);
        var local = normalizedVersionText(localTitle);
        return VERSION_MARKERS.stream().anyMatch(marker ->
            hasMarker(remote, marker) != hasMarker(local, marker)
        );
    }

    private String normalizedVersionText(String value) {
        return Normalizer.normalize(value == null ? "" : value, Normalizer.Form.NFKC)
            .toLowerCase(Locale.ROOT);
    }

    private String fileName(String value) {
        if (value == null) {
            return "";
        }
        return value.substring(Math.max(value.lastIndexOf('/'), value.lastIndexOf('\\')) + 1);
    }

    private static String normalizedTitleForSimilarity(String value) {
        var normalized = Normalizer.normalize(value, Normalizer.Form.NFKC).toLowerCase(Locale.ROOT);
        for (var marker : VERSION_MARKERS) {
            if (marker.chars().allMatch(character -> character < 128)) {
                normalized = normalized.replaceAll("\\b" + Pattern.quote(marker) + "\\b", " ");
            } else {
                normalized = normalized.replace(marker, " ");
            }
        }
        return normalizedText(normalized);
    }

    private static String normalizedBaseTitle(String value) {
        var result = value == null ? "" : value;
        String previous;
        do {
            previous = result;
            result = BRACKETED_CONTENT.matcher(result).replaceAll(" ");
        } while (!result.equals(previous));
        return normalizedText(result);
    }

    private static boolean hasMarker(String title, String marker) {
        if (marker.chars().allMatch(character -> character < 128)) {
            return Pattern.compile("\\b" + Pattern.quote(marker) + "\\b").matcher(title).find();
        }
        return title.contains(marker);
    }

    private static double artistOverlap(String left, String right) {
        var leftArtists = normalizedArtistSet(left);
        var rightArtists = normalizedArtistSet(right);
        if (leftArtists.isEmpty() || rightArtists.isEmpty()) {
            return 0;
        }
        var intersection = leftArtists.stream().filter(rightArtists::contains).count();
        return (double) intersection / Math.max(leftArtists.size(), rightArtists.size());
    }

    private static Set<String> normalizedArtistSet(String value) {
        var artists = normalizedArtists(value);
        return artists.isEmpty() ? Set.of() : Set.of(artists.split("/"));
    }

    private static double similarity(String left, String right) {
        if (left.isEmpty() || right.isEmpty()) {
            return 0;
        }
        if (left.equals(right)) {
            return 1;
        }
        var previous = new int[right.length() + 1];
        var current = new int[right.length() + 1];
        for (var column = 0; column <= right.length(); column++) {
            previous[column] = column;
        }
        for (var row = 1; row <= left.length(); row++) {
            current[0] = row;
            for (var column = 1; column <= right.length(); column++) {
                var cost = left.charAt(row - 1) == right.charAt(column - 1) ? 0 : 1;
                current[column] = Math.min(
                    Math.min(current[column - 1] + 1, previous[column] + 1),
                    previous[column - 1] + cost
                );
            }
            var swap = previous;
            previous = current;
            current = swap;
        }
        return 1.0 - (double) previous[right.length()] / Math.max(left.length(), right.length());
    }

    private static Comparator<LocalTrack> localQualityComparator() {
        return Comparator.comparingInt((LocalTrack track) -> codecQuality(track.codec()))
            .thenComparingInt(track -> track.bitDepth() == null ? 0 : track.bitDepth())
            .thenComparingInt(track -> track.sampleRate() == null ? 0 : track.sampleRate())
            .thenComparingLong(LocalTrack::fileSize)
            .reversed()
            .thenComparing(LocalTrack::trackId);
    }

    private static int codecQuality(String codec) {
        var value = codec == null ? "" : codec.toUpperCase(Locale.ROOT);
        if (value.contains("DSD") || value.contains("DSF") || value.contains("DFF")) {
            return 5;
        }
        if (value.contains("FLAC") || value.contains("ALAC") || value.contains("APE")
            || value.contains("WAV") || value.contains("AIFF") || value.contains("WV")) {
            return 4;
        }
        if (value.contains("OPUS") || value.contains("AAC") || value.contains("OGG")
            || value.contains("M4A")) {
            return 2;
        }
        if (value.contains("MP3") || value.contains("WMA")) {
            return 1;
        }
        return 0;
    }

    record MatchResult(Optional<String> exactTrackId, List<Suggestion> suggestions) {
    }

    record Suggestion(
        String trackId, String title, String artist, String album, long durationMs, int score
    ) {
    }

    private record LocalTrack(
        String trackId, String path, String title, String artist, String album, long durationMs,
        String codec, Integer sampleRate, Integer bitDepth, long fileSize
    ) {
    }

    private record ScoredTrack(LocalTrack track, double score) {
    }
}
