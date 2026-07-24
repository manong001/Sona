package cc.eu.sosee.sona.download;

import java.util.List;
import org.springframework.web.util.HtmlUtils;

public record DownloadPlaylistPreview(
    String name, String artworkUrl, List<DownloadCandidate> items
) {
    public DownloadPlaylistPreview {
        name = name == null ? null : HtmlUtils.htmlUnescape(name);
    }

    public DownloadPlaylistPreview(String name, List<DownloadCandidate> items) {
        this(name, null, items);
    }
}
