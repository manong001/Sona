package cc.eu.sosee.sona.release;

import cc.eu.sosee.sona.config.SonaProperties;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Clock;
import java.util.Locale;
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
    private final Path releaseDirectory;
    private final Clock clock;

    AppReleaseService(SonaProperties properties, Clock clock) {
        releaseDirectory = properties.getDataDir().toAbsolutePath().normalize().resolve("releases");
        this.clock = clock;
    }

    Optional<AppRelease> latest() {
        return latest(AppReleasePlatform.IOS);
    }

    Optional<AppRelease> latest(AppReleasePlatform platform) {
        var manifest = releaseDirectory.resolve(platform.manifestName());
        var packagePath = releaseDirectory.resolve(platform.packageName());
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
                platform.packageName()
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
        return publish(version, build, notes, file, AppReleasePlatform.IOS);
    }

    AppRelease publish(
        String version,
        int build,
        String notes,
        MultipartFile file,
        AppReleasePlatform platform
    ) {
        validateMetadata(version, build, notes);
        if (file == null || file.isEmpty()) {
            throw new ResponseStatusException(
                HttpStatus.BAD_REQUEST,
                platform.packageLabel() + " 文件不能为空"
            );
        }
        try {
            Files.createDirectories(releaseDirectory);
            var temporaryPackage = Files.createTempFile(
                releaseDirectory,
                "Sona-",
                "." + platform.fileExtension() + ".tmp"
            );
            try {
                try (var input = file.getInputStream()) {
                    Files.copy(input, temporaryPackage, StandardCopyOption.REPLACE_EXISTING);
                }
                validatePackage(temporaryPackage, file, platform);
                moveReplacing(temporaryPackage, releaseDirectory.resolve(platform.packageName()));
            } finally {
                Files.deleteIfExists(temporaryPackage);
            }

            var release = new AppRelease(
                version.strip(),
                build,
                notes == null ? "" : notes.strip(),
                clock.millis(),
                Files.size(releaseDirectory.resolve(platform.packageName())),
                platform.packageName()
            );
            writeManifest(release, platform);
            return release;
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (IOException exception) {
            throw new ResponseStatusException(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "保存 " + platform.packageLabel() + " 安装包失败",
                exception
            );
        }
    }

    Path packagePath(AppRelease release) {
        var path = releaseDirectory.resolve(release.fileName()).normalize();
        if (!path.startsWith(releaseDirectory) || !Files.isRegularFile(path)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "服务器暂无对应安装包");
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

    private void validatePackage(
        Path path,
        MultipartFile file,
        AppReleasePlatform platform
    ) {
        if (platform == AppReleasePlatform.IOS) {
            validateIpa(path);
            return;
        }
        validateDmg(path, file.getOriginalFilename());
    }

    private void validateDmg(Path path, String originalFilename) {
        if (originalFilename == null
            || !originalFilename.toLowerCase(Locale.ROOT).endsWith(".dmg")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "DMG 文件扩展名无效");
        }
        try {
            var size = Files.size(path);
            if (size < 512) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "DMG 包结构无效");
            }
            try (var input = Files.newByteChannel(path)) {
                input.position(size - 512);
                var signature = java.nio.ByteBuffer.allocate(4);
                if (input.read(signature) != 4
                    || signature.get(0) != 'k'
                    || signature.get(1) != 'o'
                    || signature.get(2) != 'l'
                    || signature.get(3) != 'y') {
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "DMG 包结构无效");
                }
            }
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (IOException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "DMG 文件无法读取", exception);
        }
    }

    private void writeManifest(AppRelease release, AppReleasePlatform platform) throws IOException {
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
            moveReplacing(temporary, releaseDirectory.resolve(platform.manifestName()));
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

enum AppReleasePlatform {
    IOS("ios", "ipa", "IPA", "Sona-unsigned.ipa", "latest.properties"),
    MACOS("macos", "dmg", "DMG", "Sona-arm64.dmg", "latest-macos.properties");

    private final String value;
    private final String fileExtension;
    private final String packageLabel;
    private final String packageName;
    private final String manifestName;

    AppReleasePlatform(
        String value,
        String fileExtension,
        String packageLabel,
        String packageName,
        String manifestName
    ) {
        this.value = value;
        this.fileExtension = fileExtension;
        this.packageLabel = packageLabel;
        this.packageName = packageName;
        this.manifestName = manifestName;
    }

    static AppReleasePlatform from(String value) {
        for (var platform : values()) {
            if (platform.value.equalsIgnoreCase(value)) {
                return platform;
            }
        }
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "不支持的客户端平台");
    }

    static AppReleasePlatform fromExtension(String extension) {
        for (var platform : values()) {
            if (platform.fileExtension.equalsIgnoreCase(extension)) {
                return platform;
            }
        }
        throw new ResponseStatusException(HttpStatus.NOT_FOUND, "不支持的安装包格式");
    }

    String fileExtension() { return fileExtension; }
    String packageLabel() { return packageLabel; }
    String packageName() { return packageName; }
    String manifestName() { return manifestName; }
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
