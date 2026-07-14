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
    long updatedAt
) {
}

