package cc.eu.sosee.sona.auth;

import org.springframework.stereotype.Service;

@Service
public class SystemNotificationService {

    private final SystemNotificationRepository repository;

    SystemNotificationService(SystemNotificationRepository repository) {
        this.repository = repository;
    }

    public void notifyPlaylistDownloadFailures(
        String userId, String playlistName, int failedCount, String failureSummary
    ) {
        repository.create(
            userId,
            "PLAYLIST_AUTOMATION_DOWNLOAD_FAILED",
            "订阅歌单下载失败",
            "《" + playlistName + "》有 " + failedCount
                + " 首歌曲下载失败：" + failureSummary
        );
    }
}
