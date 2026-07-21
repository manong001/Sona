package cc.eu.sosee.sona;

import cc.eu.sosee.sona.config.SonaProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication(exclude = UserDetailsServiceAutoConfiguration.class)
@EnableConfigurationProperties(SonaProperties.class)
@EnableScheduling
public class SonaApplication {

    public static void main(String[] args) {
        SpringApplication.run(SonaApplication.class, args);
    }
}
