package cc.eu.sosee.sona.config;

import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

@Component
@Order(0)
class SchemaMigration implements ApplicationRunner {

    private final JdbcClient jdbcClient;

    SchemaMigration(JdbcClient jdbcClient) {
        this.jdbcClient = jdbcClient;
    }

    @Override
    public void run(ApplicationArguments arguments) {
        Set<String> columns = jdbcClient.sql("PRAGMA table_info(users)")
            .query((resultSet, rowNumber) -> resultSet.getString("name"))
            .list()
            .stream()
            .collect(Collectors.toSet());
        if (!columns.contains("role")) {
            jdbcClient.sql("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'USER'").update();
        }
        if (!columns.contains("enabled")) {
            jdbcClient.sql("ALTER TABLE users ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1").update();
        }
    }
}
