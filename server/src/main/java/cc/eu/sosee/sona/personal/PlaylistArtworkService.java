package cc.eu.sosee.sona.personal;

import cc.eu.sosee.sona.config.SonaProperties;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import javax.imageio.ImageIO;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;
import static org.springframework.http.HttpStatus.NOT_FOUND;
import static org.springframework.http.HttpStatus.PAYLOAD_TOO_LARGE;

@Service
class PlaylistArtworkService {

    private static final long MAX_BYTES = 8L * 1024 * 1024;
    private static final int EDGE = 1200;

    private final PersonalRepository repository;
    private final Path artworkDirectory;
    private final Clock clock;

    PlaylistArtworkService(PersonalRepository repository, SonaProperties properties, Clock clock) {
        this.repository = repository;
        artworkDirectory = properties.getDataDir().resolve("playlist-artwork").normalize();
        this.clock = clock;
    }

    PersonalRepository.PlaylistData upload(
        String userId, String playlistId, MultipartFile file
    ) {
        if (file.isEmpty()) {
            throw new ResponseStatusException(BAD_REQUEST, "Artwork file is empty");
        }
        if (file.getSize() > MAX_BYTES) {
            throw new ResponseStatusException(PAYLOAD_TOO_LARGE, "Artwork must not exceed 8 MB");
        }
        try {
            var source = ImageIO.read(new ByteArrayInputStream(file.getBytes()));
            if (source == null) {
                throw new ResponseStatusException(BAD_REQUEST, "Unsupported artwork image");
            }
            var side = Math.min(source.getWidth(), source.getHeight());
            var x = (source.getWidth() - side) / 2;
            var y = (source.getHeight() - side) / 2;
            var outputSide = Math.min(side, EDGE);
            var output = new BufferedImage(outputSide, outputSide, BufferedImage.TYPE_INT_RGB);
            Graphics2D graphics = output.createGraphics();
            graphics.setColor(Color.BLACK);
            graphics.fillRect(0, 0, outputSide, outputSide);
            graphics.setRenderingHint(
                RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC
            );
            graphics.drawImage(
                source, 0, 0, outputSide, outputSide, x, y, x + side, y + side, null
            );
            graphics.dispose();
            Files.createDirectories(artworkDirectory);
            if (!ImageIO.write(output, "jpg", artworkPath(playlistId).toFile())) {
                throw new IOException("JPEG encoder unavailable");
            }
            var playlist = repository.setPlaylistUploadedArtwork(
                userId, playlistId, "upload:" + clock.millis()
            );
            if (playlist.isEmpty()) {
                deleteFile(playlistId);
                throw new ResponseStatusException(NOT_FOUND, "Playlist not found");
            }
            return playlist.get();
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (IOException exception) {
            throw new ResponseStatusException(BAD_REQUEST, "Unable to process artwork image", exception);
        }
    }

    PersonalRepository.PlaylistData selectTrack(
        String userId, String playlistId, String trackId
    ) {
        var playlist = repository.setPlaylistArtwork(userId, playlistId, trackId)
            .orElseThrow(() -> new ResponseStatusException(
                NOT_FOUND, "Playlist track artwork not found"
            ));
        deleteFile(playlistId);
        return playlist;
    }

    PersonalRepository.PlaylistData clear(String userId, String playlistId) {
        var playlist = repository.clearPlaylistArtwork(userId, playlistId)
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Playlist not found"));
        deleteFile(playlistId);
        return playlist;
    }

    PersonalRepository.PlaylistData selectSource(String userId, String playlistId) {
        var playlist = repository.setPlaylistSourceArtwork(userId, playlistId)
            .orElseThrow(() -> new ResponseStatusException(
                NOT_FOUND, "Playlist subscription artwork not found"
            ));
        deleteFile(playlistId);
        return playlist;
    }

    byte[] read(String userId, String playlistId) {
        if (!repository.canAccessPlaylist(userId, playlistId)) {
            throw new ResponseStatusException(NOT_FOUND, "Playlist not found");
        }
        try {
            return Files.readAllBytes(artworkPath(playlistId));
        } catch (IOException exception) {
            throw new ResponseStatusException(NOT_FOUND, "Playlist artwork not found");
        }
    }

    private Path artworkPath(String playlistId) {
        return artworkDirectory.resolve(playlistId + ".jpg");
    }

    private void deleteFile(String playlistId) {
        try {
            Files.deleteIfExists(artworkPath(playlistId));
        } catch (IOException ignored) {
            // 旧封面清理失败不应阻止切换封面来源。
        }
    }
}
