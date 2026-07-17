package cc.eu.sosee.sona.social;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import cc.eu.sosee.sona.config.SonaProperties;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;
import static org.springframework.http.HttpStatus.FORBIDDEN;
import static org.springframework.http.HttpStatus.INTERNAL_SERVER_ERROR;
import static org.springframework.http.HttpStatus.PAYLOAD_TOO_LARGE;

@Service
class SocialMediaService {

    private static final Set<String> KINDS = Set.of("IMAGE", "GIF", "LIVE_PHOTO", "VIDEO");
    private static final Set<String> IMAGE_TYPES = Set.of(
        "image/jpeg", "image/png", "image/heic", "image/heif", "image/webp", "image/gif"
    );
    private static final Set<String> VIDEO_TYPES = Set.of(
        "video/mp4", "video/quicktime", "video/x-m4v"
    );
    private static final long MAX_IMAGE_BYTES = 20L * 1024 * 1024;
    private static final long MAX_VIDEO_BYTES = 1024L * 1024 * 1024;

    private final SocialRepository repository;
    private final Path mediaDirectory;

    SocialMediaService(SocialRepository repository, SonaProperties properties) {
        this.repository = repository;
        this.mediaDirectory = properties.getDataDir().resolve("social-media").toAbsolutePath().normalize();
    }

    SocialMediaResponse upload(
        AuthenticatedUser actor,
        MultipartFile file,
        String kind,
        String requestedName,
        String groupId,
        String component
    ) {
        var normalizedKind = kind == null ? "" : kind.toUpperCase(Locale.ROOT);
        if (!KINDS.contains(normalizedKind) || file.isEmpty()) {
            throw new ResponseStatusException(BAD_REQUEST, "Invalid social media upload");
        }
        var mimeType = file.getContentType() == null
            ? "application/octet-stream" : file.getContentType().toLowerCase(Locale.ROOT);
        var videoLike = normalizedKind.equals("VIDEO")
            || normalizedKind.equals("LIVE_PHOTO") && VIDEO_TYPES.contains(mimeType);
        if (videoLike ? !VIDEO_TYPES.contains(mimeType) : !IMAGE_TYPES.contains(mimeType)) {
            throw new ResponseStatusException(BAD_REQUEST, "Unsupported social media type");
        }
        var limit = videoLike ? MAX_VIDEO_BYTES : MAX_IMAGE_BYTES;
        if (file.getSize() > limit) {
            throw new ResponseStatusException(
                PAYLOAD_TOO_LARGE,
                videoLike ? "Video must not exceed 1 GB" : "Image must not exceed 20 MB"
            );
        }
        var originalName = safeName(requestedName == null ? file.getOriginalFilename() : requestedName);
        var storageName = UUID.randomUUID() + extension(originalName, mimeType);
        try {
            Files.createDirectories(mediaDirectory);
            var temporary = Files.createTempFile(mediaDirectory, "upload-", ".tmp");
            try {
                file.transferTo(temporary);
                Files.move(
                    temporary,
                    mediaDirectory.resolve(storageName),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING
                );
            } finally {
                Files.deleteIfExists(temporary);
            }
        } catch (IOException exception) {
            throw new ResponseStatusException(INTERNAL_SERVER_ERROR, "Could not save social media");
        }
        return repository.addMedia(
            actor.id(), normalizedKind, mimeType, originalName, storageName,
            file.getSize(), groupId, component
        ).response();
    }

    MediaDownload download(AuthenticatedUser actor, String id) {
        var media = repository.media(id);
        if (!repository.canAccessMedia(actor.id(), media)) {
            throw new ResponseStatusException(FORBIDDEN, "Media is not visible");
        }
        var path = mediaDirectory.resolve(media.storagePath()).normalize();
        if (!path.startsWith(mediaDirectory) || !Files.isRegularFile(path)) {
            throw new ResponseStatusException(BAD_REQUEST, "Media file is unavailable");
        }
        return new MediaDownload(new FileSystemResource(path), media.mimeType(), media.originalName());
    }

    private static String safeName(String value) {
        var candidate = value == null ? "media" : value;
        candidate = candidate.replace('\\', '/');
        candidate = candidate.substring(candidate.lastIndexOf('/') + 1);
        candidate = candidate.replaceAll("[\\r\\n\\\"\\x00]", "_").strip();
        return candidate.isBlank() ? "media" : candidate.substring(0, Math.min(candidate.length(), 160));
    }

    private static String extension(String name, String mimeType) {
        var index = name.lastIndexOf('.');
        if (index >= 0 && index >= name.length() - 10) {
            return name.substring(index).toLowerCase(Locale.ROOT);
        }
        return switch (mimeType) {
            case "image/png" -> ".png";
            case "image/gif" -> ".gif";
            case "image/heic" -> ".heic";
            case "image/heif" -> ".heif";
            case "video/quicktime" -> ".mov";
            case "video/mp4" -> ".mp4";
            default -> ".jpg";
        };
    }

    record MediaDownload(Resource resource, String mimeType, String originalName) {
    }
}
