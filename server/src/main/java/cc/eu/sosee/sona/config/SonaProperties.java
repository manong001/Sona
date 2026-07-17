package cc.eu.sosee.sona.config;

import java.nio.file.Path;
import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "sona")
public class SonaProperties {

    private Path musicDir = Path.of("./music");
    private Path dataDir = Path.of("./data");
    private String publicUrl = "http://localhost:6699";
    private boolean scanOnStartup = true;
    private boolean scrapingEnabled = true;
    private final Auth auth = new Auth();
    private final Downloader downloader = new Downloader();
    private final Ai ai = new Ai();

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

    public Downloader getDownloader() {
        return downloader;
    }

    public Ai getAi() {
        return ai;
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

    public static class Downloader {

        private boolean enabled;
        private String baseUrl = "http://sona-downloader:6700";
        private String token = "";

        public boolean isEnabled() {
            return enabled;
        }

        public void setEnabled(boolean enabled) {
            this.enabled = enabled;
        }

        public String getBaseUrl() {
            return baseUrl;
        }

        public void setBaseUrl(String baseUrl) {
            this.baseUrl = baseUrl;
        }

        public String getToken() {
            return token;
        }

        public void setToken(String token) {
            this.token = token;
        }
    }

    public static class Ai {

        private boolean enabled;
        private String baseUrl = "https://api.openai.com/v1";
        private String apiKey = "";
        private String model = "";
        private Duration timeout = Duration.ofSeconds(30);

        public boolean isEnabled() {
            return enabled;
        }

        public void setEnabled(boolean enabled) {
            this.enabled = enabled;
        }

        public String getBaseUrl() {
            return baseUrl;
        }

        public void setBaseUrl(String baseUrl) {
            this.baseUrl = baseUrl;
        }

        public String getApiKey() {
            return apiKey;
        }

        public void setApiKey(String apiKey) {
            this.apiKey = apiKey;
        }

        public String getModel() {
            return model;
        }

        public void setModel(String model) {
            this.model = model;
        }

        public Duration getTimeout() {
            return timeout;
        }

        public void setTimeout(Duration timeout) {
            this.timeout = timeout;
        }

    }
}
