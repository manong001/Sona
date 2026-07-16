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
}
