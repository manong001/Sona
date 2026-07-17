package cc.eu.sosee.sona.personal;

import cc.eu.sosee.sona.config.SonaProperties;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.time.Clock;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DirectoryPlaylistService {

    private static final String UPLOAD_DIRECTORY = "Uploads";
    private static final String NEW_TRACKS_PLAYLIST = "新增歌曲";
    private static final Pattern YEAR_PREFIX = Pattern.compile(
        "^(\\d{4})(?:\\s*[-_.]\\s*|\\s+)(.+)$"
    );
    private static final Pattern AUDIO_FORMAT_SUFFIX = Pattern.compile(
        "\\s*\\[(?:mp3|m4a|aac|flac|alac|wav|aiff|aif|ogg|oga|opus|ape|wv|tta)\\]\\s*$",
        Pattern.CASE_INSENSITIVE
    );

    private final JdbcClient jdbcClient;
    private final Clock clock;
    private final Path musicDirectory;

    DirectoryPlaylistService(JdbcClient jdbcClient, Clock clock, SonaProperties properties) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
        this.musicDirectory = properties.getMusicDir().toAbsolutePath().normalize();
    }

    @Transactional
    public void sync() throws IOException {
        var ownerId = ownerId();
        if (ownerId.isEmpty() || !Files.isDirectory(musicDirectory)) {
            return;
        }

        var directoryPaths = new HashSet<String>();
        for (var directory : leafDirectories()) {
            var relativePath = relative(directory);
            directoryPaths.add(relativePath);
            var playlist = findOrCreate(ownerId.get(), directory, relativePath);
            syncTracks(playlist.id(), playlist.poolType(), directory);
        }

        pruneStalePlaylists(directoryPaths.stream().toList());
    }

    @Transactional
    public void pruneStalePlaylists(List<String> directoryPaths) {
        var currentPaths = new HashSet<>(directoryPaths);
        var stalePlaylists = jdbcClient.sql("""
                SELECT id, directory_path FROM playlists
                WHERE directory_path IS NOT NULL
                """)
            .query((resultSet, rowNumber) -> new DirectoryPlaylist(
                resultSet.getString("id"), resultSet.getString("directory_path"), "NORMAL"
            ))
            .list();
        for (var playlist : stalePlaylists) {
            if (!currentPaths.contains(playlist.directoryPath())) {
                jdbcClient.sql("DELETE FROM playlists WHERE id = :id")
                    .param("id", playlist.id())
                    .update();
            }
        }
    }

    public List<String> leafDirectoryPaths() throws IOException {
        if (!Files.isDirectory(musicDirectory)) {
            return List.of();
        }
        return leafDirectories().stream().map(this::relative).toList();
    }

    @Transactional
    public void sync(String relativePath) {
        var ownerId = ownerId();
        var directory = musicDirectory.resolve(relativePath).normalize();
        if (ownerId.isEmpty()
            || directory.equals(musicDirectory)
            || !directory.startsWith(musicDirectory)
            || !Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)) {
            return;
        }
        var playlist = findOrCreate(ownerId.get(), directory, relative(directory));
        syncTracks(playlist.id(), playlist.poolType(), directory);
    }

    private Optional<String> ownerId() {
        return jdbcClient.sql("""
                SELECT id FROM users
                WHERE role = 'ADMIN' AND enabled = 1
                ORDER BY created_at, id
                LIMIT 1
                """)
            .query(String.class)
            .optional();
    }

    private List<Path> leafDirectories() throws IOException {
        try (var paths = Files.walk(musicDirectory)) {
            return paths
                .filter(path -> !path.equals(musicDirectory))
                .filter(path -> Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS))
                .filter(this::hasNoChildDirectories)
                .sorted()
                .toList();
        }
    }

    private boolean hasNoChildDirectories(Path directory) {
        try (var children = Files.list(directory)) {
            return children.noneMatch(path -> Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS));
        } catch (IOException exception) {
            return false;
        }
    }

    private DirectoryPlaylist findOrCreate(String ownerId, Path directory, String relativePath) {
        var existing = jdbcClient.sql("""
                SELECT id, directory_path, pool_type FROM playlists
                WHERE directory_path = :directoryPath
                """)
            .param("directoryPath", relativePath)
            .query((resultSet, rowNumber) -> new DirectoryPlaylist(
                resultSet.getString("id"),
                resultSet.getString("directory_path"),
                resultSet.getString("pool_type")
            ))
            .optional();
        if (existing.isPresent()) {
            renameGeneratedPlaylist(existing.get(), directory, relativePath);
            return existing.get();
        }

        var playlist = new DirectoryPlaylist(UUID.randomUUID().toString(), relativePath, "NORMAL");
        jdbcClient.sql("""
                INSERT INTO playlists(
                    id, user_id, name, featured, directory_path, pool_type, created_at
                ) VALUES (
                    :id, :userId, :name, 1, :directoryPath, :poolType, :createdAt
                )
                """)
            .param("id", playlist.id())
            .param("userId", ownerId)
            .param("name", playlistName(directory, relativePath))
            .param("directoryPath", relativePath)
            .param("poolType", playlist.poolType())
            .param("createdAt", clock.millis())
            .update();
        return playlist;
    }

    private void renameGeneratedPlaylist(
        DirectoryPlaylist playlist, Path directory, String relativePath
    ) {
        var oldName = directory.getFileName().toString();
        var legacyName = formatYearPrefix(oldName);
        var newName = playlistName(directory, relativePath);
        if (oldName.equals(newName) && legacyName.equals(newName)) {
            return;
        }
        jdbcClient.sql("""
                UPDATE playlists SET name = :newName
                WHERE id = :id AND (name = :oldName OR name = :legacyName)
                """)
            .param("newName", newName)
            .param("id", playlist.id())
            .param("oldName", oldName)
            .param("legacyName", legacyName)
            .update();
    }

    private String playlistName(Path directory, String relativePath) {
        if (UPLOAD_DIRECTORY.equals(relativePath)) {
            return NEW_TRACKS_PLAYLIST;
        }
        var directoryName = directory.getFileName().toString();
        var withoutFormat = AUDIO_FORMAT_SUFFIX.matcher(directoryName).replaceFirst("").strip();
        return formatYearPrefix(withoutFormat);
    }

    private String formatYearPrefix(String name) {
        var matcher = YEAR_PREFIX.matcher(name);
        return matcher.matches()
            ? matcher.group(2).strip() + "（" + matcher.group(1) + "）"
            : name;
    }

    private void syncTracks(String playlistId, String poolType, Path directory) {
        var prefix = directory.toAbsolutePath().normalize() + directory.getFileSystem().getSeparator();
        var trackIds = jdbcClient.sql("""
                SELECT id FROM tracks
                WHERE substr(path, 1, length(:pathPrefix)) = :pathPrefix
                ORDER BY path, id
                """)
            .param("pathPrefix", prefix)
            .query(String.class)
            .list();

        jdbcClient.sql("DELETE FROM playlist_tracks WHERE playlist_id = :playlistId")
            .param("playlistId", playlistId)
            .update();
        for (var position = 0; position < trackIds.size(); position++) {
            jdbcClient.sql("""
                    INSERT INTO playlist_tracks(playlist_id, track_id, position, added_at)
                    VALUES (:playlistId, :trackId, :position, :addedAt)
                    """)
                .param("playlistId", playlistId)
                .param("trackId", trackIds.get(position))
                .param("position", position)
                .param("addedAt", clock.millis())
                .update();
        }
        jdbcClient.sql("""
                UPDATE tracks SET pool_type = :poolType
                WHERE substr(path, 1, length(:pathPrefix)) = :pathPrefix
                """)
            .param("poolType", poolType)
            .param("pathPrefix", prefix)
            .update();
    }

    private String relative(Path directory) {
        return musicDirectory.relativize(directory.toAbsolutePath().normalize())
            .toString()
            .replace('\\', '/');
    }

    private record DirectoryPlaylist(String id, String directoryPath, String poolType) {
    }
}
