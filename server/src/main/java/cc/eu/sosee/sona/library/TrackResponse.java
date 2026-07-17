package cc.eu.sosee.sona.library;

import java.util.List;

record TrackResponse(
    String id,
    String title,
    String artist,
    String album,
    Integer trackNumber,
    long durationMs,
    String codec,
    String fileExtension,
    Integer sampleRate,
    Integer bitDepth,
    String artworkURL,
    String streamURL,
    boolean hasLyrics,
    String metadataStatus,
    String poolType,
    String audienceType,
    String genre,
    List<String> relatedGenres,
    String region,
    List<String> artists
) {

    static TrackResponse from(TrackRecord track) {
        var basePath = "/api/v1/tracks/" + track.id();
        var canonicalArtist = ArtistNames.canonical(track.artist());
        return new TrackResponse(
            track.id(),
            track.title(),
            canonicalArtist,
            track.album(),
            track.trackNumber(),
            track.durationMs(),
            track.codec(),
            extension(track),
            track.sampleRate(),
            track.bitDepth(),
            track.artworkPath() == null ? null : basePath + "/artwork",
            basePath + "/stream",
            track.plainLyrics() != null || track.syncedLyrics() != null,
            track.metadataStatus(),
            track.poolType(),
            track.audienceType(),
            track.genre(),
            track.relatedGenres(),
            track.region(),
            canonicalArtist.isEmpty() ? List.of() : List.of(canonicalArtist)
        );
    }

    private static String extension(TrackRecord track) {
        var filename = track.path().getFileName().toString();
        var separator = filename.lastIndexOf('.');
        return separator < 0 ? "" : filename.substring(separator + 1).toLowerCase();
    }
}
