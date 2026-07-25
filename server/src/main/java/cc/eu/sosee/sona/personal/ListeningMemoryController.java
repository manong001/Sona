package cc.eu.sosee.sona.personal;

import cc.eu.sosee.sona.auth.AuthenticatedUser;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;

@RestController
@RequestMapping("/api/v1/me/listening-memories")
class ListeningMemoryController {

    private static final DateTimeFormatter DAY_FORMAT = DateTimeFormatter.ofPattern("M月d日");
    private final JdbcClient jdbcClient;
    private final Clock clock;

    ListeningMemoryController(JdbcClient jdbcClient, Clock clock) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
    }

    @GetMapping
    List<ListeningMemory> memories(
        @AuthenticationPrincipal AuthenticatedUser user,
        @RequestParam(defaultValue = "UTC") String timezone
    ) {
        ZoneId zoneId;
        try {
            zoneId = ZoneId.of(timezone);
        } catch (RuntimeException exception) {
            throw new ResponseStatusException(BAD_REQUEST, "Invalid timezone");
        }
        var now = Instant.now(clock);
        var today = now.atZone(zoneId).toLocalDate();
        var result = new ArrayList<ListeningMemory>();
        onThisDay(user.id(), today.minusYears(1).atStartOfDay(zoneId).toInstant(),
            today.minusYears(1).plusDays(1).atStartOfDay(zoneId).toInstant(), today)
            .ifPresent(result::add);
        favoriteAnniversary(user.id(), today.minusYears(1).atStartOfDay(zoneId).toInstant(),
            today.minusYears(1).plusDays(1).atStartOfDay(zoneId).toInstant())
            .ifPresent(result::add);
        dormant(user.id(), now.minus(Duration.ofDays(90))).ifPresent(result::add);
        monthlyTop(user.id(), now.minus(Duration.ofDays(30))).ifPresent(result::add);
        return result;
    }

    private java.util.Optional<ListeningMemory> onThisDay(
        String userId, Instant start, Instant end, java.time.LocalDate today
    ) {
        return jdbcClient.sql("""
                SELECT tracks.id, tracks.title, tracks.artist, tracks.artwork_path,
                       tracks.updated_at, playback_records.played_at
                FROM playback_records
                JOIN tracks ON tracks.id = playback_records.track_id
                WHERE playback_records.user_id = :userId
                  AND playback_records.played_at >= :start
                  AND playback_records.played_at < :end
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId
                      AND hidden_tracks.track_id = tracks.id
                  )
                ORDER BY playback_records.listened_ms DESC, playback_records.played_at DESC
                LIMIT 1
                """)
            .param("userId", userId)
            .param("start", start.toEpochMilli())
            .param("end", end.toEpochMilli())
            .query((resultSet, rowNumber) -> memory(
                "on-this-day-" + resultSet.getString("id"),
                "ON_THIS_DAY",
                "去年今日",
                today.minusYears(1).format(DAY_FORMAT) + "，你听过这首歌",
                resultSet
            ))
            .optional();
    }

    private java.util.Optional<ListeningMemory> favoriteAnniversary(
        String userId, Instant start, Instant end
    ) {
        return jdbcClient.sql("""
                SELECT tracks.id, tracks.title, tracks.artist, tracks.artwork_path,
                       tracks.updated_at, favorites.created_at AS played_at
                FROM favorites
                JOIN tracks ON tracks.id = favorites.track_id
                WHERE favorites.user_id = :userId
                  AND favorites.created_at >= :start
                  AND favorites.created_at < :end
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId
                      AND hidden_tracks.track_id = tracks.id
                  )
                ORDER BY favorites.created_at
                LIMIT 1
                """)
            .param("userId", userId)
            .param("start", start.toEpochMilli())
            .param("end", end.toEpochMilli())
            .query((resultSet, rowNumber) -> memory(
                "favorite-anniversary-" + resultSet.getString("id"),
                "FAVORITE_ANNIVERSARY",
                "收藏一周年",
                "一年前的今天，你收藏了这首歌",
                resultSet
            ))
            .optional();
    }

    private java.util.Optional<ListeningMemory> dormant(String userId, Instant before) {
        return jdbcClient.sql("""
                SELECT tracks.id, tracks.title, tracks.artist, tracks.artwork_path,
                       tracks.updated_at, MAX(playback_records.played_at) AS played_at
                FROM playback_records
                JOIN tracks ON tracks.id = playback_records.track_id
                WHERE playback_records.user_id = :userId
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId
                      AND hidden_tracks.track_id = tracks.id
                  )
                GROUP BY tracks.id
                HAVING MAX(playback_records.played_at) < :before
                ORDER BY MAX(playback_records.played_at)
                LIMIT 1
                """)
            .param("userId", userId)
            .param("before", before.toEpochMilli())
            .query((resultSet, rowNumber) -> memory(
                "dormant-" + resultSet.getString("id"),
                "LONG_AGO",
                "好久不见",
                "超过 90 天没有听过它了",
                resultSet
            ))
            .optional();
    }

    private java.util.Optional<ListeningMemory> monthlyTop(String userId, Instant since) {
        return jdbcClient.sql("""
                SELECT tracks.id, tracks.title, tracks.artist, tracks.artwork_path,
                       tracks.updated_at, MAX(playback_records.played_at) AS played_at,
                       COUNT(*) AS play_count
                FROM playback_records
                JOIN tracks ON tracks.id = playback_records.track_id
                WHERE playback_records.user_id = :userId
                  AND playback_records.played_at >= :since
                  AND NOT EXISTS (
                    SELECT 1 FROM hidden_tracks
                    WHERE hidden_tracks.user_id = :userId
                      AND hidden_tracks.track_id = tracks.id
                  )
                GROUP BY tracks.id
                ORDER BY play_count DESC, played_at DESC
                LIMIT 1
                """)
            .param("userId", userId)
            .param("since", since.toEpochMilli())
            .query((resultSet, rowNumber) -> memory(
                "monthly-top-" + resultSet.getString("id"),
                "MONTHLY_TOP",
                "最近循环最多",
                "近 30 天播放 " + resultSet.getInt("play_count") + " 次",
                resultSet
            ))
            .optional();
    }

    private static ListeningMemory memory(
        String id, String type, String title, String subtitle, java.sql.ResultSet resultSet
    ) throws java.sql.SQLException {
        var trackId = resultSet.getString("id");
        var artwork = resultSet.getString("artwork_path") == null
            ? null : "/api/v1/tracks/" + trackId + "/artwork?v=" + resultSet.getLong("updated_at");
        return new ListeningMemory(
            id, type, title, subtitle, trackId, resultSet.getString("title"),
            resultSet.getString("artist"), artwork, resultSet.getLong("played_at")
        );
    }

    record ListeningMemory(
        String id, String type, String title, String subtitle, String trackId,
        String trackTitle, String artist, String artworkURL, long occurredAt
    ) {
    }
}
