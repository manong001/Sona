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

    public List<String> addDownloadedFiles(String playlistId, List<String> relativeFiles) {
        var files = relativeFiles.stream().map(this::resolveFile).distinct().toList();
        scanFiles(files);
        var trackIds = repository.addPlaylistTracksByPaths(playlistId, files);
        if (trackIds.isEmpty()) {
            throw new IllegalStateException("歌曲已下载，但扫描后未找到可加入歌单的曲目");
        }
        return trackIds;
    }

    public void scanDownloadedFiles(List<String> relativeFiles) {
        scanFiles(relativeFiles.stream().map(this::resolveFile).distinct().toList());
    }

    public List<String> findDownloadedTrackIds(List<String> relativeFiles) {
        var files = relativeFiles.stream().map(this::resolveFile).distinct().toList();
        return repository.trackIdsByPaths(files);
    }

    private void scanFiles(List<Path> files) {
        var directories = files.stream()
            .map(Path::getParent)
            .distinct()
            .toList();
        for (var directory : directories) {
            var filesInDirectory = files.stream()
                .filter(path -> path.getParent().equals(directory))
                .toList();
            scanCoordinator.enqueueFiles(
                musicDirectory.relativize(directory).toString(), filesInDirectory
            ).join();
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

    public void setRemoteArtwork(String userId, String playlistId, String artworkUrl) {
        var normalizedUrl = artworkUrl.strip();
        if (!normalizedUrl.startsWith("https://") && !normalizedUrl.startsWith("http://")) {
            return;
        }
        repository.setPlaylistRemoteArtwork(userId, playlistId, normalizedUrl);
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
