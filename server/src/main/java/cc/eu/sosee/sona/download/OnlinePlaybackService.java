package cc.eu.sosee.sona.download;

import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class OnlinePlaybackService {

    private final DownloaderGateway gateway;
    private final OnlinePlaybackSettingsRepository settings;

    OnlinePlaybackService(DownloaderGateway gateway, OnlinePlaybackSettingsRepository settings) {
        this.gateway = gateway;
        this.settings = settings;
    }

    public List<OnlinePlaybackSource> sources() {
        return settings.findAll();
    }

    public void setEnabled(String id, boolean enabled) {
        settings.setEnabled(id, enabled);
    }

    public String resolve(String title, String artist, long durationMs) {
        if (!gateway.isEnabled()) {
            throw new IllegalStateException("音乐下载服务未启用，无法解析在线播放兜底");
        }
        var enabled = settings.findAll().stream().filter(OnlinePlaybackSource::enabled)
            .map(OnlinePlaybackSource::id).toList();
        if (enabled.isEmpty()) {
            throw new IllegalStateException("未启用在线播放音源");
        }
        return gateway.resolvePlaybackFallback(title, artist, durationMs, enabled);
    }
}
