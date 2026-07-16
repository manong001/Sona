package cc.eu.sosee.sona.personal;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

@Service
class AchievementService {

    private static final List<LevelDefinition> LEVELS = List.of(
        new LevelDefinition("listener", "静候知音", "LISTENER", 0, "headphones"),
        new LevelDefinition("beginner", "初声乐迷", "FIRST NOTE", 1, "music.note"),
        new LevelDefinition("silver", "银弦听众", "SILVER LISTENER", 5, "music.quarternote.3"),
        new LevelDefinition("collector", "旋律收藏家", "MELODY COLLECTOR", 15, "square.stack.fill"),
        new LevelDefinition("gold", "金唱片鉴赏家", "GOLDEN EAR", 30, "record.circle.fill"),
        new LevelDefinition("star", "星海乐评人", "STAR CURATOR", 60, "sparkles"),
        new LevelDefinition("master", "殿堂级乐迷", "MUSIC MASTER", 100, "crown.fill")
    );

    private final JdbcClient jdbcClient;
    private final Clock clock;

    AchievementService(JdbcClient jdbcClient, Clock clock) {
        this.jdbcClient = jdbcClient;
        this.clock = clock;
    }

    AchievementSummary summary(String userId, ZoneId zoneId) {
        var rows = jdbcClient.sql("""
                SELECT track_id, listened_ms, played_at
                FROM playback_records
                WHERE user_id = :userId
                ORDER BY played_at
                """)
            .param("userId", userId)
            .query((resultSet, rowNumber) -> new PlaybackRow(
                resultSet.getString("track_id"),
                resultSet.getLong("listened_ms"),
                resultSet.getLong("played_at")
            ))
            .list();
        var stats = stats(rows, zoneId);
        return new AchievementSummary(
            level(stats.total()),
            stats,
            badges(stats),
            recentHistory(userId)
        );
    }

    private Stats stats(List<PlaybackRow> rows, ZoneId zoneId) {
        Map<LocalDate, Integer> daily = new LinkedHashMap<>();
        var uniqueTracks = new java.util.HashSet<String>();
        long listenedMs = 0;
        var nightListens = 0;
        for (var row : rows) {
            var dateTime = Instant.ofEpochMilli(row.playedAt()).atZone(zoneId);
            daily.merge(dateTime.toLocalDate(), 1, Integer::sum);
            uniqueTracks.add(row.trackId());
            listenedMs += row.listenedMs();
            if (dateTime.getHour() < 6) {
                nightListens++;
            }
        }
        var days = daily.keySet().stream().sorted().toList();
        var longestStreak = 0;
        var streak = 0;
        LocalDate previous = null;
        for (var day : days) {
            streak = previous != null && previous.plusDays(1).equals(day) ? streak + 1 : 1;
            longestStreak = Math.max(longestStreak, streak);
            previous = day;
        }
        return new Stats(
            rows.size(),
            daily.getOrDefault(LocalDate.now(clock.withZone(zoneId)), 0),
            uniqueTracks.size(),
            daily.values().stream().max(Integer::compareTo).orElse(0),
            longestStreak,
            nightListens,
            listenedMs
        );
    }

    private Level level(int total) {
        var index = 0;
        for (var candidate = 0; candidate < LEVELS.size(); candidate++) {
            if (total >= LEVELS.get(candidate).minimum()) {
                index = candidate;
            }
        }
        var current = LEVELS.get(index);
        var next = index + 1 < LEVELS.size() ? LEVELS.get(index + 1) : null;
        return new Level(
            current.id(), current.title(), current.englishTitle(), current.icon(), current.minimum(),
            next == null ? null : next.title(), next == null ? null : next.minimum()
        );
    }

    private List<Badge> badges(Stats stats) {
        return List.of(
            new Badge("first", "初次聆听", "完成第一次有效聆听", "music.note", stats.total() >= 1),
            new Badge("ten", "十曲入耳", "累计聆听 10 次", "medal.fill", stats.total() >= 10),
            new Badge("thirty", "金色旋律", "累计聆听 30 次", "record.circle", stats.total() >= 30),
            new Badge("streak", "连续乐章", "连续 3 天聆听", "flame.fill", stats.longestStreak() >= 3),
            new Badge("daily", "单日循环", "单日聆听 5 次", "repeat", stats.bestDaily() >= 5),
            new Badge("explorer", "曲库探索者", "聆听 10 首不同歌曲", "music.note.list", stats.uniqueTracks() >= 10),
            new Badge("night", "午夜电台", "凌晨聆听 3 次", "moon.stars.fill", stats.nightListens() >= 3),
            new Badge("legend", "百曲传奇", "累计聆听 100 次", "star.fill", stats.total() >= 100)
        );
    }

    private List<HistoryItem> recentHistory(String userId) {
        return jdbcClient.sql("""
                SELECT playback_records.track_id, tracks.title, tracks.artist,
                       playback_records.listened_ms, playback_records.progress_percent,
                       playback_records.played_at
                FROM playback_records
                LEFT JOIN tracks ON tracks.id = playback_records.track_id
                WHERE playback_records.user_id = :userId
                ORDER BY playback_records.played_at DESC
                LIMIT 20
                """)
            .param("userId", userId)
            .query((resultSet, rowNumber) -> new HistoryItem(
                resultSet.getString("track_id"),
                resultSet.getString("title") == null ? "已移除歌曲" : resultSet.getString("title"),
                resultSet.getString("artist") == null ? "未知歌手" : resultSet.getString("artist"),
                resultSet.getLong("listened_ms"),
                resultSet.getDouble("progress_percent"),
                resultSet.getLong("played_at")
            ))
            .list();
    }

    private record LevelDefinition(
        String id, String title, String englishTitle, int minimum, String icon
    ) {
    }

    private record PlaybackRow(String trackId, long listenedMs, long playedAt) {
    }

    record AchievementSummary(Level level, Stats stats, List<Badge> badges, List<HistoryItem> history) {
    }

    record Level(
        String id, String title, String englishTitle, String icon, int minimum,
        String nextTitle, Integer nextThreshold
    ) {
    }

    record Stats(
        int total, int today, int uniqueTracks, int bestDaily, int longestStreak,
        int nightListens, long listenedMs
    ) {
    }

    record Badge(String id, String title, String detail, String icon, boolean unlocked) {
    }

    record HistoryItem(
        String trackId, String title, String artist, long listenedMs,
        double progressPercent, long playedAt
    ) {
    }
}
