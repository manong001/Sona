package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.download.DownloadCandidate;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

final class MetadataCandidateMatcher {

    private MetadataCandidateMatcher() {
    }

    static Optional<Match> best(ScrapeRequest request, List<DownloadCandidate> candidates) {
        return candidates.stream()
            .map(candidate -> score(request, candidate))
            .flatMap(Optional::stream)
            .max(Comparator.comparingInt(Match::score));
    }

    private static Optional<Match> score(ScrapeRequest request, DownloadCandidate candidate) {
        var titleScore = similarity(request.title(), candidate.title(), 4, 2);
        if (titleScore < 4) {
            return Optional.empty();
        }

        var artistKnown = known(request.artist(), "Unknown Artist");
        var artistScore = artistKnown
            ? similarity(request.artist(), candidate.artist(), 3, 2)
            : 0;
        if (artistKnown && artistScore == 0) {
            return Optional.empty();
        }

        var durationScore = durationScore(request.durationMs(), candidate.durationMs());
        if (!artistKnown && durationScore < 2) {
            return Optional.empty();
        }
        if (durationScore < 0) {
            return Optional.empty();
        }

        var albumKnown = known(request.album(), "Unknown Album");
        var albumScore = albumKnown
            ? similarity(request.album(), candidate.album(), 2, 1)
            : 0;
        var total = titleScore + artistScore + Math.max(0, durationScore) + albumScore;
        var minimum = artistKnown ? 7 : 6;
        if (total < minimum) {
            return Optional.empty();
        }
        var possible = 4 + (artistKnown ? 3 : 0) + 2 + (albumKnown ? 2 : 0);
        var confidence = Math.min(100, Math.round(total * 100f / possible));
        return Optional.of(new Match(candidate, total, confidence));
    }

    private static int similarity(String local, String remote, int exact, int partial) {
        var first = compact(local);
        var second = compact(remote);
        if (first.isEmpty() || second.isEmpty()) {
            return 0;
        }
        if (first.equals(second)) {
            return exact;
        }
        return first.contains(second) || second.contains(first) ? partial : 0;
    }

    private static int durationScore(long local, Long remote) {
        if (local <= 0 || remote == null || remote <= 0) {
            return 0;
        }
        var difference = Math.abs(local - remote);
        if (difference <= 5_000) {
            return 2;
        }
        if (difference <= 15_000) {
            return 1;
        }
        return difference > 30_000 ? -1 : 0;
    }

    private static String compact(String value) {
        return TextNormalizer.sortKey(value).replaceAll("[\\p{P}\\p{S}\\s]+", "");
    }

    private static boolean known(String value, String placeholder) {
        return value != null && !value.isBlank() && !placeholder.equalsIgnoreCase(value);
    }

    record Match(DownloadCandidate candidate, int score, int confidence) {
    }
}
