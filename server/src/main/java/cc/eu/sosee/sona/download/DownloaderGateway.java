package cc.eu.sosee.sona.download;

import java.util.List;
import java.util.Optional;

public interface DownloaderGateway {

    boolean isEnabled();

    List<DownloadSource> sources();

    List<DownloadCandidate> search(String query);

    default List<DownloadCandidate> search(String query, List<String> sources) {
        return search(query);
    }

    DownloadPlaylistPreview parsePlaylist(String url);

    List<String> download(String candidateId);

    default List<String> download(String candidateId, String taskId) {
        return download(candidateId);
    }

    default List<String> download(String candidateId, String taskId, boolean strictMode) {
        return download(candidateId, taskId);
    }

    default void cancel(String taskId) {
    }

    default Optional<DownloadProgress> progress(String taskId) {
        return Optional.empty();
    }

    String resolvePlaybackFallback(String title, String artist, long durationMs, List<String> sources);
}
