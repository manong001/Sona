package cc.eu.sosee.sona.download;

import java.util.List;

public record DownloadTask(
    String id,
    String candidateId,
    String source,
    String sourceName,
    String title,
    String artist,
    String album,
    String quality,
    String artworkUrl,
    String targetPlaylistId,
    String requestedBy,
    DownloadTaskState state,
    List<String> files,
    String message,
    Long downloadedBytes,
    Long totalBytes,
    Long bytesPerSecond,
    long createdAt,
    long updatedAt
) {
    DownloadTask(
        String id, String candidateId, String source, String sourceName,
        String title, String artist, String album, String quality,
        String artworkUrl, String targetPlaylistId, String requestedBy,
        DownloadTaskState state, List<String> files, String message,
        long createdAt, long updatedAt
    ) {
        this(
            id, candidateId, source, sourceName, title, artist, album, quality,
            artworkUrl, targetPlaylistId, requestedBy, state, files, message,
            null, null, null, createdAt, updatedAt
        );
    }

    DownloadTask withProgress(DownloadProgress progress) {
        return new DownloadTask(
            id, candidateId, source, sourceName, title, artist, album, quality,
            artworkUrl, targetPlaylistId, requestedBy, state, files, message,
            progress.downloadedBytes(), progress.totalBytes(), progress.bytesPerSecond(),
            createdAt, updatedAt
        );
    }
}
