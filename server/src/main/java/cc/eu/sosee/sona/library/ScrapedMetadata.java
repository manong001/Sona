package cc.eu.sosee.sona.library;

record ScrapedMetadata(
    String title,
    String artist,
    String album,
    String plainLyrics,
    String syncedLyrics,
    byte[] artwork,
    String artworkMimeType,
    String lyricsSource,
    String metadataSource,
    int confidence
) {

    ScrapedMetadata(
        String album,
        String plainLyrics,
        String syncedLyrics,
        byte[] artwork,
        String artworkMimeType
    ) {
        this(
            null,
            null,
            album,
            plainLyrics,
            syncedLyrics,
            artwork,
            artworkMimeType,
            "lrclib",
            "remote",
            100
        );
    }

    static ScrapedMetadata empty() {
        return new ScrapedMetadata(
            null, null, null, null, null, null, null, null, null, 0
        );
    }

    boolean hasValues() {
        return hasText(title)
            || hasText(artist)
            || hasText(album)
            || hasText(plainLyrics)
            || hasText(syncedLyrics)
            || artwork != null && artwork.length > 0;
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }
}
