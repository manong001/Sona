package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.config.SonaProperties;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
class ServerMusicDirectoryService {

    private final Path musicDirectory;

    ServerMusicDirectoryService(SonaProperties properties) {
        musicDirectory = properties.getMusicDir().toAbsolutePath().normalize();
    }

    ServerMusicDirectoryListing list(String relativePath) {
        var directory = resolve(relativePath);
        try (var paths = Files.list(directory)) {
            var directories = paths
                .filter(path -> Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS))
                .sorted(Comparator.comparing(
                    path -> path.getFileName().toString(),
                    String.CASE_INSENSITIVE_ORDER
                ))
                .map(path -> new ServerMusicDirectory(
                    relative(path),
                    path.getFileName().toString(),
                    hasChildDirectory(path)
                ))
                .toList();
            var name = directory.equals(musicDirectory)
                ? rootName(directory)
                : directory.getFileName().toString();
            return new ServerMusicDirectoryListing(relative(directory), name, directories);
        } catch (IOException exception) {
            throw new ResponseStatusException(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "无法读取服务器音乐目录",
                exception
            );
        }
    }

    Path resolve(String relativePath) {
        try {
            var root = musicDirectory;
            var realRoot = realRoot();
            var value = relativePath == null ? "" : relativePath.strip();
            var relative = value.isEmpty() ? Path.of("") : Path.of(value).normalize();
            if (relative.isAbsolute() || relative.startsWith("..")) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "目录路径无效");
            }
            var candidate = root.resolve(relative).normalize();
            if (!candidate.startsWith(root)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "目录路径无效");
            }
            var realDirectory = candidate.toRealPath();
            if (!realDirectory.startsWith(realRoot) || !Files.isDirectory(realDirectory)) {
                throw new ResponseStatusException(HttpStatus.NOT_FOUND, "服务器音乐目录不存在");
            }
            return candidate;
        } catch (InvalidPathException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "目录路径无效", exception);
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (IOException exception) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "服务器音乐目录不存在", exception);
        }
    }

    private Path realRoot() throws IOException {
        return musicDirectory.toRealPath();
    }

    private String relative(Path path) {
        return musicDirectory.relativize(path.toAbsolutePath().normalize())
            .toString()
            .replace('\\', '/');
    }

    private boolean hasChildDirectory(Path directory) {
        try (var paths = Files.list(directory)) {
            return paths.anyMatch(path -> Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS));
        } catch (IOException exception) {
            return false;
        }
    }

    private String rootName(Path root) {
        return root.getFileName() == null ? "音乐目录" : root.getFileName().toString();
    }
}

record ServerMusicDirectory(String path, String name, boolean hasChildren) {
}

record ServerMusicDirectoryListing(
    String path,
    String name,
    List<ServerMusicDirectory> directories
) {
}
