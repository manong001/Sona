package cc.eu.sosee.sona.download;

import java.util.List;

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

    default void cancel(String taskId) {
    }

    String resolvePlaybackFallback(String title, String artist, long durationMs, List<String> sources);
}
