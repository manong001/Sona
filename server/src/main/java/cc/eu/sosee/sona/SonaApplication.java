package cc.eu.sosee.sona;

import cc.eu.sosee.sona.config.SonaProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration;

@SpringBootApplication(exclude = UserDetailsServiceAutoConfiguration.class)
@EnableConfigurationProperties(SonaProperties.class)
public class SonaApplication {

    public static void main(String[] args) {
        SpringApplication.run(SonaApplication.class, args);
    }
}
