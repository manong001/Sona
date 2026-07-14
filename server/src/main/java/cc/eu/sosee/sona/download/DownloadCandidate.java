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
    String lyrics
) {
}
