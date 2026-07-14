package cc.eu.sosee.sona.library;

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
    String metadataStatus
) {

    static TrackResponse from(TrackRecord track) {
        var basePath = "/api/v1/tracks/" + track.id();
        return new TrackResponse(
            track.id(),
            track.title(),
            track.artist(),
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
            track.metadataStatus()
        );
    }

    private static String extension(TrackRecord track) {
        var filename = track.path().getFileName().toString();
        var separator = filename.lastIndexOf('.');
        return separator < 0 ? "" : filename.substring(separator + 1).toLowerCase();
    }
}
