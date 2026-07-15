package cc.eu.sosee.sona.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Files;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.sqlite.SQLiteDataSource;

class SchemaMigrationTest {

    @Test
    void addsUserColumnsToExistingDatabase() throws Exception {
        var database = Files.createTempFile("sona-old-schema-", ".db");
        var dataSource = new SQLiteDataSource();
        dataSource.setUrl("jdbc:sqlite:" + database);
        var jdbcClient = JdbcClient.create(dataSource);
        jdbcClient.sql("""
                CREATE TABLE users (
                    id TEXT PRIMARY KEY,
                    username TEXT NOT NULL UNIQUE,
                    password_hash TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                )
                """)
            .update();
        jdbcClient.sql("""
                INSERT INTO users(id, username, password_hash, created_at)
                VALUES ('existing', 'admin', 'hash', 1)
                """)
            .update();

        new SchemaMigration(jdbcClient).run(null);

        var columns = jdbcClient.sql("PRAGMA table_info(users)")
            .query((resultSet, rowNumber) -> resultSet.getString("name"))
            .list();
        assertThat(columns).contains("role", "enabled");
        assertThat(jdbcClient.sql("SELECT role FROM users WHERE id = 'existing'")
            .query(String.class).single()).isEqualTo("USER");
        assertThat(jdbcClient.sql("SELECT enabled FROM users WHERE id = 'existing'")
            .query(Integer.class).single()).isEqualTo(1);
    }

    @Test
    void keepsExistingTracksNormalButDefaultsFutureTracksToPending() throws Exception {
        var database = Files.createTempFile("sona-track-schema-", ".db");
        var dataSource = new SQLiteDataSource();
        dataSource.setUrl("jdbc:sqlite:" + database);
        var jdbcClient = JdbcClient.create(dataSource);
        jdbcClient.sql("CREATE TABLE tracks(id TEXT PRIMARY KEY)").update();
        jdbcClient.sql("INSERT INTO tracks(id) VALUES ('existing')").update();

        new SchemaMigration(jdbcClient).run(null);
        jdbcClient.sql("INSERT INTO tracks(id) VALUES ('future')").update();

        assertThat(jdbcClient.sql("SELECT pool_type FROM tracks WHERE id = 'existing'")
            .query(String.class).single()).isEqualTo("NORMAL");
        assertThat(jdbcClient.sql("SELECT pool_type FROM tracks WHERE id = 'future'")
            .query(String.class).single()).isEqualTo("PENDING");
        var columns = jdbcClient.sql("PRAGMA table_info(tracks)")
            .query((resultSet, rowNumber) -> resultSet.getString("name"))
            .list();
        assertThat(columns).contains("genre", "region");
        assertThat(jdbcClient.sql("SELECT genre FROM tracks WHERE id = 'future'")
            .query(String.class).single()).isEqualTo("未分类");
        assertThat(jdbcClient.sql("SELECT region FROM tracks WHERE id = 'future'")
            .query(String.class).single()).isEqualTo("OTHER");
    }
}
