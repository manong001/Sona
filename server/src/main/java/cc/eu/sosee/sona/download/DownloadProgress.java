package cc.eu.sosee.sona.download;

public record DownloadProgress(
    long downloadedBytes,
    Long totalBytes,
    long bytesPerSecond
) {
}
