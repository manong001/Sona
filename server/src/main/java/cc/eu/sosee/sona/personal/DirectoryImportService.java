package cc.eu.sosee.sona.personal;

import cc.eu.sosee.sona.library.ScanCoordinator;
import cc.eu.sosee.sona.library.ServerMusicDirectoryService;
import java.nio.file.Path;
import org.springframework.stereotype.Service;

@Service
class DirectoryImportService {

    private final PersonalRepository repository;
    private final ServerMusicDirectoryService directoryService;
    private final ScanCoordinator scanCoordinator;

    DirectoryImportService(
        PersonalRepository repository,
        ServerMusicDirectoryService directoryService,
        ScanCoordinator scanCoordinator
    ) {
        this.repository = repository;
        this.directoryService = directoryService;
        this.scanCoordinator = scanCoordinator;
    }

    DirectoryImportResult importFavorites(String userId, String relativeDirectory) {
        return start(
            userId,
            "FAVORITE_DIRECTORY",
            relativeDirectory,
            "收藏",
            directory -> repository.addFavoritesFromDirectory(userId, directory)
        );
    }

    DirectoryImportResult importPlaylist(
        String userId, String playlistId, String playlistName, String relativeDirectory
    ) {
        return start(
            userId,
            "PLAYLIST_DIRECTORY",
            relativeDirectory,
            playlistName,
            directory -> repository.addPlaylistTracksFromDirectory(playlistId, directory)
        );
    }

    private DirectoryImportResult start(
        String userId,
        String type,
        String relativeDirectory,
        String target,
        DirectoryAssociation association
    ) {
        var directory = directoryService.resolve(relativeDirectory);
        var source = directory.getFileName() == null ? directory.toString() : directory.getFileName().toString();
        var record = repository.createImportRecord(userId, type, source, target, 0);
        repository.promotePendingTracksFromDirectory(directory);
        var immediatelyAdded = association.add(directory);
        repository.updateImportRecord(
            userId, record.id(), "RUNNING", null, immediatelyAdded, 0,
            null, null, null, null, immediatelyAdded,
            "已快速加入，正在扫描目录…"
        );
        scanCoordinator.enqueue(relativeDirectory).whenComplete((scan, exception) -> {
            if (exception != null) {
                repository.updateImportRecord(
                    userId, record.id(), "FAILED", null, immediatelyAdded, 1,
                    null, null, null, null, immediatelyAdded,
                    conciseMessage(exception)
                );
                return;
            }
            try {
                repository.refreshDirectoryIndex(directory);
                var addedAfterScan = association.add(directory);
                repository.updateImportRecord(
                    userId, record.id(), "COMPLETED", scan.discovered(), immediatelyAdded + addedAfterScan,
                    scan.failed(), scan.discovered(), scan.imported(), scan.updated(), scan.skipped(),
                    immediatelyAdded + addedAfterScan,
                    "扫描完成，已补入新发现歌曲"
                );
            } catch (Exception finalizationException) {
                repository.updateImportRecord(
                    userId, record.id(), "FAILED", scan.discovered(), immediatelyAdded,
                    Math.max(scan.failed(), 1), scan.discovered(), scan.imported(), scan.updated(),
                    scan.skipped(), immediatelyAdded, conciseMessage(finalizationException)
                );
            }
        });
        return new DirectoryImportResult(record.id(), immediatelyAdded, true);
    }

    private String conciseMessage(Throwable exception) {
        var message = exception.getMessage();
        if (message == null || message.isBlank()) {
            message = exception.getClass().getSimpleName();
        }
        return message.length() <= 500 ? message : message.substring(0, 500);
    }

    private interface DirectoryAssociation {
        int add(Path directory);
    }

    record DirectoryImportResult(String importRecordId, int importedCount, boolean scanning) {
    }
}
