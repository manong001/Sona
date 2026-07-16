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
    long createdAt,
    long updatedAt
) {
}
