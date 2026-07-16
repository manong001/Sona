package cc.eu.sosee.sona.download;

import java.util.List;

public record DownloadPlaylistPreview(String name, List<DownloadCandidate> items) {
}
