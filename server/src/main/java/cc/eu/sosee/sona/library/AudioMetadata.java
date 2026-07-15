package cc.eu.sosee.sona.library;

record AudioMetadata(
    String title,
    String artist,
    String album,
    Integer trackNumber,
    long durationMs,
    String codec,
    Integer sampleRate,
    Integer bitDepth,
    byte[] artwork,
    String artworkMimeType,
    String lyrics,
    String genre
) {
    AudioMetadata(
        String title, String artist, String album, Integer trackNumber, long durationMs,
        String codec, Integer sampleRate, Integer bitDepth, byte[] artwork,
        String artworkMimeType, String lyrics
    ) {
        this(
            title, artist, album, trackNumber, durationMs, codec, sampleRate, bitDepth,
            artwork, artworkMimeType, lyrics, ""
        );
    }
}
