package cc.eu.sosee.sona.download;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.util.Base64;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class DownloadTaskRepository {

    private final JdbcClient jdbcClient;
    private final Clock clock;

    DownloadTaskRepository(JdbcClient jdbcClient, Clock clock) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
    }

    DownloadTask create(DownloadCandidate candidate, String requestedBy) {
        return create(candidate, requestedBy, null, false);
    }

    DownloadTask create(DownloadCandidate candidate, String requestedBy, String targetPlaylistId) {
        return create(candidate, requestedBy, targetPlaylistId, true);
    }

    DownloadTask create(
        DownloadCandidate candidate, String requestedBy, String targetPlaylistId,
        boolean strictMatch
    ) {
        var now = clock.millis();
        var task = new DownloadTask(
            UUID.randomUUID().toString(),
            candidate.candidateId(),
            candidate.source(),
            candidate.sourceName(),
            candidate.title().strip(),
            candidate.artist().strip(),
            text(candidate.album()),
            text(candidate.quality()),
            blankToNull(candidate.artworkUrl()),
            targetPlaylistId,
            requestedBy,
            DownloadTaskState.QUEUED,
            List.of(),
            null,
            now,
            now
        );
        jdbcClient.sql("""
                INSERT INTO download_tasks (
                    id, candidate_id, source, source_name, title, artist, album, quality,
                    artwork_url, target_playlist_id, strict_match, requested_by, state,
                    files_json, message, created_at, updated_at
                ) VALUES (
                    :id, :candidateId, :source, :sourceName, :title, :artist, :album, :quality,
                    :artworkUrl, :targetPlaylistId, :strictMatch, :requestedBy, :state,
                    :files, :message, :createdAt, :updatedAt
                )
                """)
            .param("id", task.id())
            .param("candidateId", task.candidateId())
            .param("source", task.source())
            .param("sourceName", task.sourceName())
            .param("title", task.title())
            .param("artist", task.artist())
            .param("album", task.album())
            .param("quality", task.quality())
            .param("artworkUrl", task.artworkUrl())
            .param("targetPlaylistId", task.targetPlaylistId())
            .param("strictMatch", strictMatch ? 1 : 0)
            .param("requestedBy", task.requestedBy())
            .param("state", task.state().name())
            .param("files", writeFiles(task.files()))
            .param("message", task.message())
            .param("createdAt", task.createdAt())
            .param("updatedAt", task.updatedAt())
            .update();
        return task;
    }

    boolean isStrictMatch(String id) {
        return jdbcClient.sql("SELECT strict_match FROM download_tasks WHERE id = :id")
            .param("id", id)
            .query(Integer.class)
            .optional()
            .orElse(0) == 1;
    }

    List<DownloadTask> findRecent(String requestedBy) {
        return jdbcClient.sql("""
                SELECT * FROM download_tasks
                WHERE requested_by = :requestedBy
                ORDER BY CASE state
                    WHEN 'RUNNING' THEN 0
                    WHEN 'QUEUED' THEN 1
                    ELSE 2
                END, updated_at DESC, created_at DESC
                LIMIT 100
                """)
            .param("requestedBy", requestedBy)
            .query(this::map)
            .list();
    }

    boolean existsInLibrary(DownloadCandidate candidate) {
        return jdbcClient.sql("""
                SELECT COUNT(*) FROM tracks
                WHERE trim(title) COLLATE NOCASE = trim(:title) COLLATE NOCASE
                  AND replace(trim(artist), '、', '/') COLLATE NOCASE =
                      replace(trim(:artist), '、', '/') COLLATE NOCASE
                """)
            .param("title", candidate.title())
            .param("artist", candidate.artist())
            .query(Integer.class)
            .single() > 0;
    }

    Optional<String> findLibraryTrackId(DownloadCandidate candidate) {
        return jdbcClient.sql("""
                SELECT id FROM tracks
                WHERE trim(title) COLLATE NOCASE = trim(:title) COLLATE NOCASE
                  AND replace(trim(artist), '、', '/') COLLATE NOCASE =
                      replace(trim(:artist), '、', '/') COLLATE NOCASE
                ORDER BY updated_at DESC, id
                LIMIT 1
                """)
            .param("title", candidate.title())
            .param("artist", candidate.artist())
            .query(String.class)
            .optional();
    }

    Optional<DownloadTaskState> findExistingState(DownloadCandidate candidate) {
        return jdbcClient.sql("""
                SELECT state FROM download_tasks
                WHERE trim(title) COLLATE NOCASE = trim(:title) COLLATE NOCASE
                  AND replace(trim(artist), '、', '/') COLLATE NOCASE =
                      replace(trim(:artist), '、', '/') COLLATE NOCASE
                  AND state IN ('QUEUED', 'RUNNING')
                ORDER BY CASE state
                    WHEN 'RUNNING' THEN 0
                    ELSE 2
                END
                LIMIT 1
                """)
            .param("title", candidate.title().strip())
            .param("artist", candidate.artist().strip())
            .query(String.class)
            .optional()
            .map(DownloadTaskState::valueOf);
    }

    Optional<DownloadTask> findById(String id) {
        return jdbcClient.sql("SELECT * FROM download_tasks WHERE id = :id")
            .param("id", id)
            .query(this::map)
            .optional();
    }

    Optional<DownloadTask> findById(String id, String requestedBy) {
        return jdbcClient.sql("""
                SELECT * FROM download_tasks
                WHERE id = :id AND requested_by = :requestedBy
                """)
            .param("id", id)
            .param("requestedBy", requestedBy)
            .query(this::map)
            .optional();
    }

    List<DownloadTask> findCompletedByTargetPlaylist(String targetPlaylistId) {
        return jdbcClient.sql("""
                SELECT * FROM download_tasks
                WHERE target_playlist_id = :targetPlaylistId
                  AND state = 'COMPLETED'
                ORDER BY updated_at DESC, created_at DESC
                LIMIT 500
                """)
            .param("targetPlaylistId", targetPlaylistId)
            .query(this::map)
            .list();
    }

    boolean delete(String id, String requestedBy) {
        return jdbcClient.sql("DELETE FROM download_tasks WHERE id = :id AND requested_by = :requestedBy")
            .param("id", id)
            .param("requestedBy", requestedBy)
            .update() == 1;
    }

    int deleteFailed(String requestedBy) {
        return jdbcClient.sql("""
                DELETE FROM download_tasks
                WHERE requested_by = :requestedBy AND state = 'FAILED'
                """)
            .param("requestedBy", requestedBy)
            .update();
    }

    int failActiveTasks(String message) {
        return jdbcClient.sql("""
                UPDATE download_tasks
                SET state = 'FAILED', message = :message, updated_at = :updatedAt
                WHERE state IN ('QUEUED', 'RUNNING')
                """)
            .param("message", message)
            .param("updatedAt", clock.millis())
            .update();
    }

    boolean markRunning(String id) {
        return jdbcClient.sql("""
                UPDATE download_tasks
                SET state = 'RUNNING', files_json = '[]', message = NULL, updated_at = :updatedAt
                WHERE id = :id AND state = 'QUEUED'
                """)
            .param("updatedAt", clock.millis())
            .param("id", id)
            .update() == 1;
    }

    void update(String id, DownloadTaskState state, List<String> files, String message) {
        jdbcClient.sql("""
                UPDATE download_tasks
                SET state = :state, files_json = :files, message = :message, updated_at = :updatedAt
                WHERE id = :id
                """)
            .param("state", state.name())
            .param("files", writeFiles(files))
            .param("message", blankToNull(message))
            .param("updatedAt", clock.millis())
            .param("id", id)
            .update();
    }

    void replaceCandidate(String id, DownloadCandidate candidate) {
        jdbcClient.sql("""
                UPDATE download_tasks
                SET candidate_id = :candidateId,
                    source = :source,
                    source_name = :sourceName,
                    album = :album,
                    quality = :quality,
                    artwork_url = :artworkUrl,
                    state = 'QUEUED',
                    files_json = '',
                    message = NULL,
                    updated_at = :updatedAt
                WHERE id = :id
                """)
            .param("candidateId", candidate.candidateId())
            .param("source", candidate.source())
            .param("sourceName", candidate.sourceName())
            .param("album", text(candidate.album()))
            .param("quality", text(candidate.quality()))
            .param("artworkUrl", blankToNull(candidate.artworkUrl()))
            .param("updatedAt", clock.millis())
            .param("id", id)
            .update();
    }

    private DownloadTask map(ResultSet resultSet, int rowNumber) throws SQLException {
        return new DownloadTask(
            resultSet.getString("id"),
            resultSet.getString("candidate_id"),
            resultSet.getString("source"),
            resultSet.getString("source_name"),
            resultSet.getString("title"),
            resultSet.getString("artist"),
            resultSet.getString("album"),
            resultSet.getString("quality"),
            resultSet.getString("artwork_url"),
            resultSet.getString("target_playlist_id"),
            resultSet.getString("requested_by"),
            DownloadTaskState.valueOf(resultSet.getString("state")),
            readFiles(resultSet.getString("files_json")),
            resultSet.getString("message"),
            resultSet.getLong("created_at"),
            resultSet.getLong("updated_at")
        );
    }

    private String writeFiles(List<String> files) {
        if (files == null || files.isEmpty()) {
            return "";
        }
        return files.stream()
            .map(value -> Base64.getUrlEncoder().withoutPadding().encodeToString(
                value.getBytes(StandardCharsets.UTF_8)
            ))
            .collect(Collectors.joining(","));
    }

    private List<String> readFiles(String value) {
        if (value == null || value.isBlank()) {
            return List.of();
        }
        try {
            return List.of(value.split(",")).stream()
                .map(encoded -> new String(Base64.getUrlDecoder().decode(encoded), StandardCharsets.UTF_8))
                .toList();
        } catch (IllegalArgumentException exception) {
            return List.of();
        }
    }

    private String text(String value) {
        return value == null ? "" : value.strip();
    }

    private String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }
}
