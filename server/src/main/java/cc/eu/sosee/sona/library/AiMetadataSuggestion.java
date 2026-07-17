package cc.eu.sosee.sona.library;

import java.util.List;

record TrackAiInput(String title, String artist, String album, String currentGenre) {
}

record AiMetadataSuggestion(
    String correctedTitle,
    String primaryGenre,
    List<String> relatedGenres,
    String reason
) {
}
