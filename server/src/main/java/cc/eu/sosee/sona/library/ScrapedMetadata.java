package cc.eu.sosee.sona.library;

record ScrapedMetadata(
    String album,
    String plainLyrics,
    String syncedLyrics,
    byte[] artwork,
    String artworkMimeType
) {

    static ScrapedMetadata empty() {
        return new ScrapedMetadata(null, null, null, null, null);
    }

    boolean hasValues() {
        return hasText(album)
            || hasText(plainLyrics)
            || hasText(syncedLyrics)
            || artwork != null && artwork.length > 0;
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }
}
