package cc.eu.sosee.sona.personal;

import cc.eu.sosee.sona.config.SonaProperties;
import cc.eu.sosee.sona.library.ScanCoordinator;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class PlaylistDownloadImportService {

    private final PersonalRepository repository;
    private final ScanCoordinator scanCoordinator;
    private final Path musicDirectory;

    PlaylistDownloadImportService(
        PersonalRepository repository,
        ScanCoordinator scanCoordinator,
        SonaProperties properties
    ) {
        this.repository = repository;
        this.scanCoordinator = scanCoordinator;
        musicDirectory = properties.getMusicDir().toAbsolutePath().normalize();
    }

    public Target create(String userId, String name) {
        var playlist = repository.createPlaylist(userId, name.strip());
        return new Target(playlist.id(), playlist.name());
    }

    public Target create(String userId, String name, String poolType) {
        var playlist = repository.createPlaylist(userId, name.strip(), poolType);
        return new Target(playlist.id(), playlist.name());
    }

    public Target createFeatured(String userId, String name) {
        var playlist = repository.createFeaturedPlaylist(userId, name.strip());
        return new Target(playlist.id(), playlist.name());
    }

    public void addDownloadedFiles(String playlistId, List<String> relativeFiles) {
        var files = relativeFiles.stream().map(this::resolveFile).distinct().toList();
        var directories = files.stream()
            .map(Path::getParent)
            .distinct()
            .map(musicDirectory::relativize)
            .map(Path::toString)
            .toList();
        for (var directory : directories) {
            scanCoordinator.enqueue(directory).join();
        }
        if (repository.addPlaylistTracksByPaths(playlistId, files) == 0) {
            throw new IllegalStateException("歌曲已下载，但扫描后未找到可加入歌单的曲目");
        }
    }

    public void replaceTracks(String userId, String playlistId, List<String> trackIds) {
        if (!repository.replacePlaylistTracks(userId, playlistId, trackIds)) {
            throw new IllegalArgumentException("订阅目标歌单不存在");
        }
    }

    public void addToHome(String userId, String playlistId) {
        if (!repository.setPlaylistShownOnHome(userId, playlistId, true)) {
            throw new IllegalArgumentException("订阅目标歌单不存在");
        }
    }

    public void rename(String userId, String playlistId, String name) {
        if (!repository.renamePlaylist(userId, playlistId, name)) {
            throw new IllegalArgumentException("订阅目标歌单不存在");
        }
    }

    public void delete(String userId, String playlistId) {
        repository.deletePlaylist(userId, playlistId);
    }

    private Path resolveFile(String relativeFile) {
        var path = musicDirectory.resolve(relativeFile).normalize();
        if (!path.startsWith(musicDirectory) || !Files.isRegularFile(path)) {
            throw new IllegalStateException("下载服务返回了无效文件路径");
        }
        return path;
    }

    public record Target(String id, String name) {
    }
}
