package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.config.SonaProperties;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.springframework.stereotype.Component;

@Component
class ArtworkStore {

    private final Path artworkDirectory;

    ArtworkStore(SonaProperties properties) throws IOException {
        artworkDirectory = properties.getDataDir().toAbsolutePath().normalize().resolve("artwork");
        Files.createDirectories(artworkDirectory);
    }

    Path save(String trackId, byte[] data, String mimeType) throws IOException {
        if (data == null || data.length == 0) {
            return null;
        }
        var extension = "image/png".equalsIgnoreCase(mimeType) ? ".png" : ".jpg";
        var target = artworkDirectory.resolve(trackId + extension);
        Files.write(target, data);
        return target;
    }
}

