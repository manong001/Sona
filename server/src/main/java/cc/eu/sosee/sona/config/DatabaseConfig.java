package cc.eu.sosee.sona.config;

import java.io.IOException;
import java.nio.file.Files;
import javax.sql.DataSource;
import org.sqlite.SQLiteConfig;
import org.sqlite.SQLiteDataSource;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class DatabaseConfig {

    @Bean
    DataSource dataSource(SonaProperties properties) throws IOException {
        var dataDirectory = properties.getDataDir().toAbsolutePath().normalize();
        Files.createDirectories(dataDirectory);

        var sqliteConfig = new SQLiteConfig();
        sqliteConfig.enforceForeignKeys(true);
        sqliteConfig.setBusyTimeout(5_000);

        var dataSource = new SQLiteDataSource(sqliteConfig);
        dataSource.setUrl("jdbc:sqlite:" + dataDirectory.resolve("sona.db"));
        return dataSource;
    }
}

