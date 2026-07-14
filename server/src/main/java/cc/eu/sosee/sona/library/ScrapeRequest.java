package cc.eu.sosee.sona.library;

record ScrapeRequest(
    String title,
    String artist,
    String album,
    long durationMs,
    boolean needsTitle,
    boolean needsArtist,
    boolean needsAlbum,
    boolean needsArtwork,
    boolean needsLyrics
) {
}
