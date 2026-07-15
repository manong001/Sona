package cc.eu.sosee.sona.library;

import java.nio.file.Path;

record TrackRecord(
    String id,
    Path path,
    long fileSize,
    long modifiedAt,
    String title,
    String normalizedTitle,
    String artist,
    String album,
    Integer trackNumber,
    long durationMs,
    String codec,
    Integer sampleRate,
    Integer bitDepth,
    Path artworkPath,
    String plainLyrics,
    String syncedLyrics,
    String lyricsSource,
    String metadataStatus,
    boolean manualEdited,
    long createdAt,
    long updatedAt,
    String poolType,
    String audienceType,
    String genre,
    String region
) {
    TrackRecord(
        String id, Path path, long fileSize, long modifiedAt, String title, String normalizedTitle,
        String artist, String album, Integer trackNumber, long durationMs, String codec,
        Integer sampleRate, Integer bitDepth, Path artworkPath, String plainLyrics,
        String syncedLyrics, String lyricsSource, String metadataStatus, boolean manualEdited,
        long createdAt, long updatedAt
    ) {
        this(
            id, path, fileSize, modifiedAt, title, normalizedTitle, artist, album, trackNumber,
            durationMs, codec, sampleRate, bitDepth, artworkPath, plainLyrics, syncedLyrics,
            lyricsSource, metadataStatus, manualEdited, createdAt, updatedAt, "PENDING", "GENERAL",
            "未分类", "OTHER"
        );
    }

    TrackRecord(
        String id, Path path, long fileSize, long modifiedAt, String title, String normalizedTitle,
        String artist, String album, Integer trackNumber, long durationMs, String codec,
        Integer sampleRate, Integer bitDepth, Path artworkPath, String plainLyrics,
        String syncedLyrics, String lyricsSource, String metadataStatus, boolean manualEdited,
        long createdAt, long updatedAt, String poolType, String audienceType
    ) {
        this(
            id, path, fileSize, modifiedAt, title, normalizedTitle, artist, album, trackNumber,
            durationMs, codec, sampleRate, bitDepth, artworkPath, plainLyrics, syncedLyrics,
            lyricsSource, metadataStatus, manualEdited, createdAt, updatedAt, poolType,
            audienceType, "未分类", "OTHER"
        );
    }
}
