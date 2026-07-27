package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.config.SonaProperties;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

@Component
class MobileAudioTranscoder {

    private static final String BITRATE = "192k";

    private final Path cacheDirectory;
    private final String ffmpegCommand;
    private final ConcurrentHashMap<Path, Object> locks = new ConcurrentHashMap<>();

    @Autowired
    MobileAudioTranscoder(SonaProperties properties) {
        this(properties.getDataDir().resolve("transcoded"), "ffmpeg");
    }

    MobileAudioTranscoder(Path cacheDirectory, String ffmpegCommand) {
        this.cacheDirectory = cacheDirectory.toAbsolutePath().normalize();
        this.ffmpegCommand = ffmpegCommand;
    }

    Path transcode(Path source, String trackID) throws IOException {
        Files.createDirectories(cacheDirectory);
        var target = cacheDirectory.resolve(cacheKey(trackID, source) + ".m4a");
        var lock = locks.computeIfAbsent(target, ignored -> new Object());
        synchronized (lock) {
            if (isCurrent(source, target)) {
                return target;
            }
            transcodeToTemporaryFile(source, target);
            return target;
        }
    }

    private boolean isCurrent(Path source, Path target) throws IOException {
        return Files.isRegularFile(target)
            && Files.size(target) > 0
            && Files.getLastModifiedTime(target).equals(Files.getLastModifiedTime(source));
    }

    private void transcodeToTemporaryFile(Path source, Path target) throws IOException {
        var temporary = Files.createTempFile(cacheDirectory, target.getFileName().toString(), ".tmp.m4a");
        try {
            var process = new ProcessBuilder(
                ffmpegCommand,
                "-v", "error",
                "-nostdin",
                "-y",
                "-i", source.toString(),
                "-map", "0:a:0",
                "-vn",
                "-c:a", "aac",
                "-b:a", BITRATE,
                "-movflags", "+faststart",
                temporary.toString()
            ).redirectErrorStream(true).start();
            var output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
            var exitCode = waitFor(process);
            if (exitCode != 0 || Files.size(temporary) == 0) {
                throw new IOException(
                    "FFmpeg 流量版转码失败" + (output.isBlank() ? "" : "：" + output.strip())
                );
            }
            moveIntoPlace(temporary, target);
            Files.setLastModifiedTime(target, Files.getLastModifiedTime(source));
        } finally {
            Files.deleteIfExists(temporary);
        }
    }

    private int waitFor(Process process) throws IOException {
        try {
            return process.waitFor();
        } catch (InterruptedException exception) {
            process.destroyForcibly();
            Thread.currentThread().interrupt();
            throw new IOException("FFmpeg 流量版转码被中断", exception);
        }
    }

    private void moveIntoPlace(Path source, Path target) throws IOException {
        try {
            Files.move(
                source, target,
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING
            );
        } catch (AtomicMoveNotSupportedException ignored) {
            Files.move(source, target, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private String cacheKey(String trackID, Path source) {
        try {
            var digest = MessageDigest.getInstance("SHA-256")
                .digest(
                    (trackID + "\0" + source.toAbsolutePath().normalize())
                        .getBytes(StandardCharsets.UTF_8)
                );
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 不可用", exception);
        }
    }
}
