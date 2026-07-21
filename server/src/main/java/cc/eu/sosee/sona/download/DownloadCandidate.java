package cc.eu.sosee.sona.download;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record DownloadCandidate(
    @NotBlank String candidateId,
    @NotBlank String source,
    @NotBlank String sourceName,
    @NotBlank @Size(max = 300) String title,
    @NotBlank @Size(max = 300) String artist,
    @Size(max = 300) String album,
    String extension,
    String quality,
    Long durationMs,
    Long fileSizeBytes,
    String artworkUrl,
    boolean hasLyrics,
    String lyrics,
    DownloadTaskState downloadState
) {
    public DownloadCandidate(
        String candidateId, String source, String sourceName, String title, String artist,
        String album, String extension, String quality, Long durationMs, Long fileSizeBytes,
        String artworkUrl, boolean hasLyrics, String lyrics
    ) {
        this(
            candidateId, source, sourceName, title, artist, album, extension, quality,
            durationMs, fileSizeBytes, artworkUrl, hasLyrics, lyrics, null
        );
    }

    DownloadCandidate withDownloadState(DownloadTaskState state) {
        return new DownloadCandidate(
            candidateId, source, sourceName, title, artist, album, extension, quality,
            durationMs, fileSizeBytes, artworkUrl, hasLyrics, lyrics, state
        );
    }
}
