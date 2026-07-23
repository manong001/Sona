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
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

@Component
class PlaylistSubscriptionMatcher {

    private static final int MAX_SUGGESTIONS = 3;
    private static final double MIN_TITLE_SIMILARITY = 0.70;
    private static final Pattern ARTIST_SEPARATOR = Pattern.compile(
        "(?i)\\s*(?:、|/|,|，|&|＆|;|；|\\bfeat\\.?\\b|\\bft\\.?\\b)\\s*"
    );
    private static final Pattern TITLE_SUFFIX = Pattern.compile(
        "\\s*(?:[\\(（\\[【\\{《<]|[-‐‑‒–—―－@＠#＃|｜/／~～:：+＋=＝_＿·•]).*$"
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
                SELECT id, title, artist, album, duration_ms
                FROM tracks ORDER BY updated_at DESC, id
                """)
            .query((resultSet, rowNumber) -> new LocalTrack(
                resultSet.getString("id"), resultSet.getString("title"),
                resultSet.getString("artist"), resultSet.getString("album"),
                resultSet.getLong("duration_ms")
            ))
            .list();
        return new Session(tracks);
    }

    static String normalizedText(String value) {
        if (value == null) {
            return "";
        }
        var normalized = Normalizer.normalize(ZhConverterUtil.toSimple(value), Normalizer.Form.NFKC)
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
        private final Map<String, List<LocalTrack>> exact = new HashMap<>();
        private final Map<String, List<LocalTrack>> strictTitles = new HashMap<>();
        private final Set<String> trackIds;

        private Session(List<LocalTrack> tracks) {
            this.tracks = tracks;
            this.trackIds = tracks.stream().map(LocalTrack::trackId).collect(java.util.stream.Collectors.toSet());
            for (var track : tracks) {
                exact.computeIfAbsent(exactKey(track.title(), track.artist()), ignored -> new ArrayList<>())
                    .add(track);
                strictTitles.computeIfAbsent(strictTitle(track.title()), ignored -> new ArrayList<>())
                    .add(track);
            }
        }

        boolean containsTrack(String trackId) {
            return trackId != null && trackIds.contains(trackId);
        }

        MatchResult match(DownloadCandidate candidate) {
            return match(candidate, Set.of());
        }

        MatchResult match(DownloadCandidate candidate, Set<String> excludedTrackIds) {
            var exactTracks = exact.getOrDefault(exactKey(candidate.title(), candidate.artist()), List.of());
            var exactTrack = exactTracks.stream()
                .filter(track -> !excludedTrackIds.contains(track.trackId()))
                .findFirst();
            if (exactTrack.isPresent()) {
                return new MatchResult(Optional.of(exactTrack.get().trackId()), List.of());
            }
            var suggestions = tracks.stream()
                .filter(track -> !excludedTrackIds.contains(track.trackId()))
                .map(track -> score(candidate, track))
                .flatMap(Optional::stream)
                .sorted(Comparator.comparingDouble(ScoredTrack::score).reversed()
                    .thenComparing(value -> value.track().trackId()))
                .limit(MAX_SUGGESTIONS)
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
            var title = strictTitle(candidate.title());
            if (title.isEmpty()) {
                return Optional.empty();
            }
            return strictTitles.getOrDefault(title, List.of()).stream()
                .filter(track -> !excludedTrackIds.contains(track.trackId()))
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

    private boolean hasVersionMismatch(String remoteTitle, String localTitle) {
        var remote = Normalizer.normalize(remoteTitle, Normalizer.Form.NFKC).toLowerCase(Locale.ROOT);
        var local = Normalizer.normalize(localTitle, Normalizer.Form.NFKC).toLowerCase(Locale.ROOT);
        return VERSION_MARKERS.stream().anyMatch(marker -> hasMarker(remote, marker) != hasMarker(local, marker));
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

    private static String strictTitle(String value) {
        if (value == null || value.isBlank()) {
            return "";
        }
        var normalized = Normalizer.normalize(
            ZhConverterUtil.toSimple(value), Normalizer.Form.NFKC
        ).toLowerCase(Locale.ROOT);
        var suffix = TITLE_SUFFIX.matcher(normalized);
        if (suffix.find()) {
            normalized = normalized.substring(0, suffix.start());
        }
        return normalizedText(normalized);
    }

    private static boolean hasMarker(String title, String marker) {
        if (marker.chars().allMatch(character -> character < 128)) {
            return Pattern.compile("\\b" + Pattern.quote(marker) + "\\b").matcher(title).find();
        }
        return title.contains(marker);
    }

    private static double artistOverlap(String left, String right) {
        var leftArtists = Set.of(normalizedArtists(left).split("/"));
        var rightArtists = Set.of(normalizedArtists(right).split("/"));
        if (leftArtists.contains("") || rightArtists.contains("")) {
            return 0;
        }
        var intersection = leftArtists.stream().filter(rightArtists::contains).count();
        return (double) intersection / Math.max(leftArtists.size(), rightArtists.size());
    }

    private static String exactKey(String title, String artist) {
        return normalizedText(title) + "\n" + normalizedArtists(artist);
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

    record MatchResult(Optional<String> exactTrackId, List<Suggestion> suggestions) {
    }

    record Suggestion(
        String trackId, String title, String artist, String album, long durationMs, int score
    ) {
    }

    private record LocalTrack(
        String trackId, String title, String artist, String album, long durationMs
    ) {
    }

    private record ScoredTrack(LocalTrack track, double score) {
    }
}
