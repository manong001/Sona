package cc.eu.sosee.sona.download;

import java.util.List;

public record DownloadPlaylistPreview(
    String name, String artworkUrl, List<DownloadCandidate> items
) {
    public DownloadPlaylistPreview(String name, List<DownloadCandidate> items) {
        this(name, null, items);
    }
}
