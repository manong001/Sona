package cc.eu.sosee.sona.personal;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.PositiveOrZero;
import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@RestController
@RequestMapping("/api/v1/me")
class PersonalController {

    private final PersonalRepository repository;

    PersonalController(PersonalRepository repository) {
        this.repository = repository;
    }

    @GetMapping("/favorites")
    FavoriteResponse favorites(@AuthenticationPrincipal AuthenticatedUser user) {
        return new FavoriteResponse(repository.favoriteTrackIds(user.id()));
    }

    @GetMapping("/favorites/tracks")
    FavoriteTrackPageResponse favoriteTracks(
        @AuthenticationPrincipal AuthenticatedUser user,
        @RequestParam(required = false) String cursor,
        @RequestParam(defaultValue = "50") int limit
    ) {
        var safeLimit = Math.max(1, Math.min(limit, 100));
        var offset = parseOffset(cursor);
        var items = new ArrayList<>(repository.favoriteTracks(user.id(), offset, safeLimit + 1));
        String nextCursor = null;
        if (items.size() > safeLimit) {
            items.remove(items.size() - 1);
            nextCursor = String.valueOf(offset + safeLimit);
        }
        return new FavoriteTrackPageResponse(items, nextCursor);
    }

    @PutMapping("/favorites/{trackId}")
    ResponseEntity<Void> addFavorite(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String trackId
    ) {
        repository.addFavorite(user.id(), trackId);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/favorites/{trackId}")
    ResponseEntity<Void> removeFavorite(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String trackId
    ) {
        repository.removeFavorite(user.id(), trackId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/playlists")
    List<PersonalRepository.PlaylistData> playlists(@AuthenticationPrincipal AuthenticatedUser user) {
        return repository.playlists(user.id());
    }

    @PostMapping("/playlists")
    ResponseEntity<PersonalRepository.PlaylistData> createPlaylist(
        @AuthenticationPrincipal AuthenticatedUser user,
        @Valid @RequestBody CreatePlaylistRequest request
    ) {
        var playlist = repository.createPlaylist(user.id(), request.name().trim());
        return ResponseEntity.created(URI.create("/api/v1/me/playlists/" + playlist.id()))
            .body(playlist);
    }

    @DeleteMapping("/playlists/{playlistId}")
    ResponseEntity<Void> deletePlaylist(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String playlistId
    ) {
        if (!repository.deletePlaylist(user.id(), playlistId)) {
            throw new ResponseStatusException(NOT_FOUND, "Playlist not found");
        }
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/playlists/{playlistId}/tracks/{trackId}")
    ResponseEntity<Void> addPlaylistTrack(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String playlistId,
        @PathVariable String trackId
    ) {
        requireOwnedPlaylist(user.id(), playlistId);
        repository.addPlaylistTrack(playlistId, trackId);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/playlists/{playlistId}/tracks/{trackId}")
    ResponseEntity<Void> removePlaylistTrack(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String playlistId,
        @PathVariable String trackId
    ) {
        requireOwnedPlaylist(user.id(), playlistId);
        repository.removePlaylistTrack(playlistId, trackId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/history")
    HistoryResponse history(@AuthenticationPrincipal AuthenticatedUser user) {
        return new HistoryResponse(repository.history(user.id()));
    }

    @PostMapping("/history/{trackId}")
    ResponseEntity<Void> recordPlayback(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String trackId,
        @Valid @RequestBody PlaybackRecordRequest request
    ) {
        repository.recordPlayback(user.id(), trackId, request.listenedMs(), request.progressPercent());
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/tracks/{trackId}")
    ResponseEntity<Void> hideTrack(
        @AuthenticationPrincipal AuthenticatedUser user,
        @PathVariable String trackId
    ) {
        repository.hideTrack(user.id(), trackId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/playback-state")
    ResponseEntity<PersonalRepository.PlaybackStateData> playbackState(
        @AuthenticationPrincipal AuthenticatedUser user
    ) {
        return ResponseEntity.ofNullable(repository.playbackState(user.id()));
    }

    @PutMapping("/playback-state")
    ResponseEntity<Void> savePlaybackState(
        @AuthenticationPrincipal AuthenticatedUser user,
        @Valid @RequestBody PlaybackStateRequest request
    ) {
        repository.savePlaybackState(
            user.id(), request.queueType(), request.queueContextId(), request.trackId(),
            request.queueTrackIds(), request.progressMs()
        );
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/playback-batches")
    ResponseEntity<Void> recordPlayedBatch(
        @AuthenticationPrincipal AuthenticatedUser user,
        @Valid @RequestBody PlaybackBatchRequest request
    ) {
        repository.recordPlayedBatch(user.id(), request.queueType(), request.queueContextId());
        return ResponseEntity.noContent().build();
    }

    private void requireOwnedPlaylist(String userId, String playlistId) {
        if (!repository.ownsPlaylist(userId, playlistId)) {
            throw new ResponseStatusException(NOT_FOUND, "Playlist not found");
        }
    }

    private int parseOffset(String cursor) {
        if (cursor == null || cursor.isBlank()) {
            return 0;
        }
        try {
            return Math.max(0, Integer.parseInt(cursor));
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(BAD_REQUEST, "Invalid favorites cursor");
        }
    }

    record FavoriteResponse(List<String> trackIds) {
    }

    record FavoriteTrackPageResponse(
        List<PersonalRepository.FavoriteTrackData> items,
        String nextCursor
    ) {
    }

    record HistoryResponse(List<PersonalRepository.HistoryData> items) {
    }

    record CreatePlaylistRequest(@NotBlank @Size(max = 80) String name) {
    }

    record PlaybackRecordRequest(
        @PositiveOrZero long listenedMs,
        @DecimalMin("0") @DecimalMax("100") double progressPercent
    ) {
    }

    record PlaybackStateRequest(
        @NotBlank String queueType,
        String queueContextId,
        @NotBlank String trackId,
        List<@NotBlank String> queueTrackIds,
        @PositiveOrZero long progressMs
    ) {
    }

    record PlaybackBatchRequest(@NotBlank String queueType, String queueContextId) {
    }
}
