package cc.eu.sosee.sona.auth;

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
import java.util.Set;
import javax.imageio.ImageIO;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;
import static org.springframework.http.HttpStatus.NOT_FOUND;
import static org.springframework.http.HttpStatus.PAYLOAD_TOO_LARGE;

@Service
class UserAvatarService {

    static final Set<String> PRESETS = Set.of(
        "aurora", "cosmos", "forest", "ocean", "sunset", "candy", "ember", "midnight"
    );
    private static final long MAX_BYTES = 5L * 1024 * 1024;
    private static final int MAX_EDGE = 1024;

    private final UserRepository userRepository;
    private final Path avatarDirectory;
    private final Clock clock;

    UserAvatarService(UserRepository userRepository, SonaProperties properties, Clock clock) {
        this.userRepository = userRepository;
        this.avatarDirectory = properties.getDataDir().resolve("avatars").normalize();
        this.clock = clock;
    }

    UserAccount selectPreset(String userId, String preset) {
        if (!PRESETS.contains(preset)) {
            throw new ResponseStatusException(BAD_REQUEST, "Unknown avatar preset");
        }
        requireUser(userId);
        deleteFile(userId);
        userRepository.setAvatar(userId, "preset:" + preset);
        return requireUser(userId);
    }

    UserAccount upload(String userId, MultipartFile file) {
        requireUser(userId);
        if (file.isEmpty()) {
            throw new ResponseStatusException(BAD_REQUEST, "Avatar file is empty");
        }
        if (file.getSize() > MAX_BYTES) {
            throw new ResponseStatusException(PAYLOAD_TOO_LARGE, "Avatar must not exceed 5 MB");
        }
        try {
            var source = ImageIO.read(new ByteArrayInputStream(file.getBytes()));
            if (source == null) {
                throw new ResponseStatusException(BAD_REQUEST, "Unsupported avatar image");
            }
            var scale = Math.min(1.0, (double) MAX_EDGE / Math.max(source.getWidth(), source.getHeight()));
            var width = Math.max(1, (int) Math.round(source.getWidth() * scale));
            var height = Math.max(1, (int) Math.round(source.getHeight() * scale));
            var output = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
            Graphics2D graphics = output.createGraphics();
            graphics.setColor(Color.WHITE);
            graphics.fillRect(0, 0, width, height);
            graphics.setRenderingHint(
                RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC
            );
            graphics.drawImage(source, 0, 0, width, height, null);
            graphics.dispose();
            Files.createDirectories(avatarDirectory);
            if (!ImageIO.write(output, "jpg", avatarPath(userId).toFile())) {
                throw new IOException("JPEG encoder unavailable");
            }
            userRepository.setAvatar(userId, "upload:" + clock.millis());
            return requireUser(userId);
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (IOException exception) {
            throw new ResponseStatusException(BAD_REQUEST, "Unable to process avatar image", exception);
        }
    }

    byte[] read(String userId) {
        var user = requireUser(userId);
        if (user.avatar() == null || !user.avatar().startsWith("upload:")) {
            throw new ResponseStatusException(NOT_FOUND, "Avatar not found");
        }
        try {
            return Files.readAllBytes(avatarPath(userId));
        } catch (IOException exception) {
            throw new ResponseStatusException(NOT_FOUND, "Avatar not found");
        }
    }

    void delete(String userId) {
        deleteFile(userId);
    }

    private UserAccount requireUser(String userId) {
        return userRepository.findById(userId)
            .orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "User not found"));
    }

    private Path avatarPath(String userId) {
        return avatarDirectory.resolve(userId + ".jpg");
    }

    private void deleteFile(String userId) {
        try {
            Files.deleteIfExists(avatarPath(userId));
        } catch (IOException ignored) {
            // A stale avatar file does not prevent changing the profile.
        }
    }
}
