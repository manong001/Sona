package cc.eu.sosee.sona.library;

import java.io.IOException;
import java.nio.file.Files;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class TrackReplacementService {

    private final TrackStore trackStore;
    private final DuplicateTrackService duplicateTrackService;

    TrackReplacementService(
        TrackStore trackStore, DuplicateTrackService duplicateTrackService
    ) {
        this.trackStore = trackStore;
        this.duplicateTrackService = duplicateTrackService;
    }

    public void requireTrack(String trackId) {
        if (trackStore.findById(trackId).isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "原歌曲不存在");
        }
    }

    public void replaceDownloadedTrack(String sourceTrackId, String targetTrackId)
        throws IOException {
        duplicateTrackService.replaceDownloadedTrack(sourceTrackId, targetTrackId);
    }

    public void discardDownloadedTrack(String trackId) {
        var track = trackStore.findById(trackId).orElse(null);
        if (track == null) {
            return;
        }
        try {
            Files.deleteIfExists(track.path());
            if (track.artworkPath() != null) {
                Files.deleteIfExists(track.artworkPath());
            }
        } catch (IOException ignored) {
            return;
        }
        trackStore.delete(trackId);
    }
}
