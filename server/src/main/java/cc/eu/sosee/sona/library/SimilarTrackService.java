package cc.eu.sosee.sona.library;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

final class SimilarTrackService {

    private SimilarTrackService() {
    }

    static List<TrackRecord> rank(
        TrackRecord target, List<String> suggestedGenres, List<TrackRecord> candidates, int limit
    ) {
        var targetGenres = normalizedGenres(target.genre(), suggestedGenres);
        return candidates.stream()
            .filter(candidate -> !candidate.id().equals(target.id()))
            .map(candidate -> new ScoredTrack(candidate, score(target, targetGenres, candidate)))
            .filter(item -> item.score() > 0)
            .sorted(Comparator.comparingInt(ScoredTrack::score).reversed()
                .thenComparing(item -> item.track().normalizedTitle())
                .thenComparing(item -> item.track().id()))
            .limit(Math.max(1, Math.min(limit, 50)))
            .map(ScoredTrack::track)
            .toList();
    }

    private static int score(TrackRecord target, Set<String> targetGenres, TrackRecord candidate) {
        var score = 0;
        for (var genre : normalizedGenres(candidate.genre(), candidate.relatedGenres())) {
            if (targetGenres.contains(genre)) {
                score += 4;
            }
        }
        if (same(target.artist(), candidate.artist())) {
            score += 2;
        }
        if (same(target.album(), candidate.album())) {
            score += 1;
        }
        return score;
    }

    private static Set<String> normalizedGenres(String primaryGenre, List<String> relatedGenres) {
        var result = new HashSet<String>();
        var values = new ArrayList<String>();
        values.add(primaryGenre);
        values.addAll(relatedGenres == null ? List.of() : relatedGenres);
        values.stream()
            .filter(value -> value != null && !value.isBlank() && !"未分类".equals(value))
            .map(value -> value.strip().toLowerCase(Locale.ROOT))
            .forEach(result::add);
        return result;
    }

    private static boolean same(String first, String second) {
        return first != null && second != null && !first.isBlank() && first.equalsIgnoreCase(second);
    }

    private record ScoredTrack(TrackRecord track, int score) {
    }
}
