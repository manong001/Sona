package cc.eu.sosee.sona.release;

import cc.eu.sosee.sona.config.SonaProperties;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Clock;
import java.util.Optional;
import java.util.Properties;
import java.util.regex.Pattern;
import java.util.zip.ZipInputStream;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

@Service
class AppReleaseService {

    private static final Pattern VERSION = Pattern.compile("[0-9]+(?:\\.[0-9]+){1,3}");
    private static final String PACKAGE_NAME = "Sona-unsigned.ipa";
    private final Path releaseDirectory;
    private final Clock clock;

    AppReleaseService(SonaProperties properties, Clock clock) {
        releaseDirectory = properties.getDataDir().toAbsolutePath().normalize().resolve("releases");
        this.clock = clock;
    }

    Optional<AppRelease> latest() {
        var manifest = releaseDirectory.resolve("latest.properties");
        var packagePath = releaseDirectory.resolve(PACKAGE_NAME);
        if (!Files.isRegularFile(manifest) || !Files.isRegularFile(packagePath)) {
            return Optional.empty();
        }
        var values = new Properties();
        try (var input = Files.newInputStream(manifest)) {
            values.load(input);
            var release = new AppRelease(
                values.getProperty("version"),
                Integer.parseInt(values.getProperty("build")),
                values.getProperty("notes", ""),
                Long.parseLong(values.getProperty("publishedAt")),
                Files.size(packagePath),
                PACKAGE_NAME
            );
            return Optional.of(release);
        } catch (Exception exception) {
            throw new ResponseStatusException(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "服务器安装包清单无效",
                exception
            );
        }
    }

    AppRelease publish(String version, int build, String notes, MultipartFile file) {
        validateMetadata(version, build, notes);
        if (file == null || file.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "IPA 文件不能为空");
        }
        try {
            Files.createDirectories(releaseDirectory);
            var temporaryPackage = Files.createTempFile(releaseDirectory, "Sona-", ".ipa.tmp");
            try {
                try (var input = file.getInputStream()) {
                    Files.copy(input, temporaryPackage, StandardCopyOption.REPLACE_EXISTING);
                }
                validateIpa(temporaryPackage);
                moveReplacing(temporaryPackage, releaseDirectory.resolve(PACKAGE_NAME));
            } finally {
                Files.deleteIfExists(temporaryPackage);
            }

            var release = new AppRelease(
                version.strip(),
                build,
                notes == null ? "" : notes.strip(),
                clock.millis(),
                Files.size(releaseDirectory.resolve(PACKAGE_NAME)),
                PACKAGE_NAME
            );
            writeManifest(release);
            return release;
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (IOException exception) {
            throw new ResponseStatusException(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "保存 IPA 安装包失败",
                exception
            );
        }
    }

    Path packagePath(AppRelease release) {
        var path = releaseDirectory.resolve(release.fileName()).normalize();
        if (!path.startsWith(releaseDirectory) || !Files.isRegularFile(path)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "服务器暂无 IPA 安装包");
        }
        return path;
    }

    private void validateMetadata(String version, int build, String notes) {
        if (version == null || !VERSION.matcher(version.strip()).matches()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "版本号格式无效");
        }
        if (build < 1) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "构建号必须大于 0");
        }
        if (notes != null && notes.length() > 4_000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "更新说明不能超过 4000 字");
        }
    }

    private void validateIpa(Path path) {
        try (var zip = new ZipInputStream(Files.newInputStream(path))) {
            boolean containsAppInfo = false;
            for (var entry = zip.getNextEntry(); entry != null; entry = zip.getNextEntry()) {
                var name = entry.getName();
                if (name.startsWith("Payload/") && name.contains(".app/")
                    && name.endsWith(".app/Info.plist")) {
                    containsAppInfo = true;
                    break;
                }
            }
            if (!containsAppInfo) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "IPA 包结构无效");
            }
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (IOException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "IPA 文件无法读取", exception);
        }
    }

    private void writeManifest(AppRelease release) throws IOException {
        var values = new Properties();
        values.setProperty("version", release.version());
        values.setProperty("build", Integer.toString(release.build()));
        values.setProperty("notes", release.notes());
        values.setProperty("publishedAt", Long.toString(release.publishedAt()));
        var temporary = Files.createTempFile(releaseDirectory, "latest-", ".tmp");
        try {
            try (var output = Files.newOutputStream(temporary)) {
                values.store(output, "Sona app release");
            }
            moveReplacing(temporary, releaseDirectory.resolve("latest.properties"));
        } finally {
            Files.deleteIfExists(temporary);
        }
    }

    private void moveReplacing(Path source, Path target) throws IOException {
        try {
            Files.move(
                source,
                target,
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING
            );
        } catch (java.nio.file.AtomicMoveNotSupportedException exception) {
            Files.move(source, target, StandardCopyOption.REPLACE_EXISTING);
        }
    }
}

record AppRelease(
    String version,
    int build,
    String notes,
    long publishedAt,
    long fileSizeBytes,
    String fileName
) {
}
