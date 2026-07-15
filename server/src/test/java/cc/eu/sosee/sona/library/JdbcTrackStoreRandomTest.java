package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Path;
import java.util.HashSet;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.sqlite.SQLiteDataSource;

class JdbcTrackStoreRandomTest {

    @TempDir
    Path temporaryDirectory;

    private JdbcClient jdbcClient;
    private JdbcTrackStore trackStore;

    @BeforeEach
    void setUp() {
        var dataSource = new SQLiteDataSource();
        dataSource.setUrl("jdbc:sqlite:" + temporaryDirectory.resolve("sona.db"));
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(dataSource);
        jdbcClient = JdbcClient.create(dataSource);
        trackStore = new JdbcTrackStore(jdbcClient);
        jdbcClient.sql("""
                INSERT INTO users(id, username, password_hash, role, enabled, created_at)
                VALUES
                  ('user-a', 'user-a', 'hash', 'USER', 1, 1),
                  ('user-b', 'user-b', 'hash', 'USER', 1, 1)
                """).update();
        for (var index = 0; index < 55; index++) {
            saveNormalTrack(index);
        }
    }

    @Test
    void coversEveryEligibleTrackBeforeAUserCanMissItAgain() {
        var first = trackStore.findRandom(50, "user-a", false);
        var second = trackStore.findRandom(50, "user-a", false);
        var covered = new HashSet<String>();
        first.forEach(track -> covered.add(track.id()));
        second.forEach(track -> covered.add(track.id()));

        assertThat(first).extracting(TrackRecord::id).doesNotHaveDuplicates().hasSize(50);
        assertThat(second).extracting(TrackRecord::id).doesNotHaveDuplicates().hasSize(50);
        assertThat(covered).hasSize(55);
        assertThat(jdbcClient.sql("""
                SELECT COUNT(*) FROM random_track_exposures WHERE user_id = 'user-a'
                """).query(Integer.class).single()).isEqualTo(55);
    }

    @Test
    void keepsCoverageStateIsolatedByUser() {
        trackStore.findRandom(50, "user-a", false);

        assertThat(jdbcClient.sql("""
                SELECT COUNT(*) FROM random_track_exposures WHERE user_id = 'user-a'
                """).query(Integer.class).single()).isEqualTo(50);
        assertThat(jdbcClient.sql("""
                SELECT COUNT(*) FROM random_track_exposures WHERE user_id = 'user-b'
                """).query(Integer.class).single()).isZero();

        trackStore.findRandom(50, "user-b", false);

        assertThat(jdbcClient.sql("""
                SELECT COUNT(*) FROM random_track_exposures WHERE user_id = 'user-b'
            """).query(Integer.class).single()).isEqualTo(50);
    }

    @Test
    void keepsChildAndFullLibraryCoverageInSeparateCycles() {
        jdbcClient.sql("""
                UPDATE tracks SET audience_type = 'CHILD'
                WHERE id IN (
                    SELECT id FROM tracks ORDER BY id LIMIT 10
                )
                """).update();

        var childTracks = trackStore.findRandom(5, "user-a", true);

        assertThat(childTracks).hasSize(5).allMatch(track -> "CHILD".equals(track.audienceType()));
        assertThat(jdbcClient.sql("""
                SELECT COUNT(*) FROM random_track_exposures
                WHERE user_id = 'user-a' AND scope = 'CHILD'
                """).query(Integer.class).single()).isEqualTo(5);
        assertThat(jdbcClient.sql("""
                SELECT COUNT(*) FROM random_track_exposures
                WHERE user_id = 'user-a' AND scope = 'ALL'
                """).query(Integer.class).single()).isZero();

        trackStore.findRandom(5, "user-a", false);

        assertThat(jdbcClient.sql("""
                SELECT COUNT(*) FROM random_track_exposures
                WHERE user_id = 'user-a' AND scope = 'ALL'
                """).query(Integer.class).single()).isEqualTo(5);
    }

    private void saveNormalTrack(int index) {
        var now = System.currentTimeMillis();
        var id = "random-cycle-" + index;
        trackStore.save(new TrackRecord(
            id,
            Path.of("/music/" + id + ".mp3"),
            1,
            now,
            "Random Cycle " + index,
            "random cycle " + index,
            "Sona",
            "Coverage",
            index,
            180_000,
            "MP3",
            44_100,
            16,
            null,
            null,
            null,
            null,
            "LOCAL",
            false,
            now,
            now,
            "NORMAL",
            "GENERAL"
        ));
    }
}
