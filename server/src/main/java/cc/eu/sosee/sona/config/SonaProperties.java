package cc.eu.sosee.sona.config;

import java.nio.file.Path;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "sona")
public class SonaProperties {

    private Path musicDir = Path.of("./music");
    private Path dataDir = Path.of("./data");
    private String publicUrl = "http://localhost:6699";
    private boolean scanOnStartup = true;
    private boolean scrapingEnabled = true;
    private final Auth auth = new Auth();

    public Path getMusicDir() {
        return musicDir;
    }

    public void setMusicDir(Path musicDir) {
        this.musicDir = musicDir;
    }

    public Path getDataDir() {
        return dataDir;
    }

    public void setDataDir(Path dataDir) {
        this.dataDir = dataDir;
    }

    public String getPublicUrl() {
        return publicUrl;
    }

    public void setPublicUrl(String publicUrl) {
        this.publicUrl = publicUrl;
    }

    public boolean isScanOnStartup() {
        return scanOnStartup;
    }

    public void setScanOnStartup(boolean scanOnStartup) {
        this.scanOnStartup = scanOnStartup;
    }

    public boolean isScrapingEnabled() {
        return scrapingEnabled;
    }

    public void setScrapingEnabled(boolean scrapingEnabled) {
        this.scrapingEnabled = scrapingEnabled;
    }

    public Auth getAuth() {
        return auth;
    }

    public static class Auth {

        private String bootstrapUsername = "admin";
        private String bootstrapPassword;
        private int sessionDays = 30;
        private boolean secureCookie;

        public String getBootstrapUsername() {
            return bootstrapUsername;
        }

        public void setBootstrapUsername(String bootstrapUsername) {
            this.bootstrapUsername = bootstrapUsername;
        }

        public String getBootstrapPassword() {
            return bootstrapPassword;
        }

        public void setBootstrapPassword(String bootstrapPassword) {
            this.bootstrapPassword = bootstrapPassword;
        }

        public int getSessionDays() {
            return sessionDays;
        }

        public void setSessionDays(int sessionDays) {
            this.sessionDays = sessionDays;
        }

        public boolean isSecureCookie() {
            return secureCookie;
        }

        public void setSecureCookie(boolean secureCookie) {
            this.secureCookie = secureCookie;
        }
    }
}
