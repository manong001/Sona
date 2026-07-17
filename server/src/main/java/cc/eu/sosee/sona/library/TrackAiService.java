package cc.eu.sosee.sona.library;

import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.NOT_FOUND;

@Service
class TrackAiService {

    private final TrackStore trackStore;
    private final OpenAiCompatibleClient client;

    TrackAiService(TrackStore trackStore, OpenAiCompatibleClient client) {
        this.trackStore = trackStore;
        this.client = client;
    }

    AiTrackAnalysis analyze(String id) {
        var track = trackStore.findById(id)
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Track not found"));
        var suggestion = client.analyze(new TrackAiInput(
            track.title(), track.artist(), track.album(), track.genre()
        ));
        var genres = new ArrayList<String>();
        genres.add(suggestion.primaryGenre());
        genres.addAll(suggestion.relatedGenres());
        var similarTracks = SimilarTrackService.rank(
            track, genres, trackStore.findSimilarCandidates(id, null, false), 10
        ).stream().map(TrackResponse::from).toList();
        return new AiTrackAnalysis(
            suggestion.correctedTitle(), suggestion.primaryGenre(), suggestion.relatedGenres(),
            suggestion.reason(), similarTracks
        );
    }

    record AiTrackAnalysis(
        String correctedTitle,
        String primaryGenre,
        List<String> relatedGenres,
        String reason,
        List<TrackResponse> similarTracks
    ) {
    }
}
