package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.config.SonaProperties;
import java.time.Duration;
import java.util.List;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
class MusicDlGateway implements DownloaderGateway {

    private final boolean enabled;
    private final String token;
    private final RestClient searchClient;
    private final RestClient downloadClient;

    MusicDlGateway(SonaProperties properties) {
        var downloader = properties.getDownloader();
        enabled = downloader.isEnabled();
        token = downloader.getToken();
        searchClient = client(downloader.getBaseUrl(), Duration.ofMinutes(3));
        downloadClient = client(downloader.getBaseUrl(), Duration.ofHours(2));
    }

    @Override
    public boolean isEnabled() {
        return enabled;
    }

    @Override
    public List<DownloadSource> sources() {
        requireEnabled();
        var response = searchClient.get()
            .uri("/v1/sources")
            .header("X-Sona-Token", token)
            .accept(MediaType.APPLICATION_JSON)
            .retrieve()
            .body(SourceEnvelope.class);
        return response == null || response.items() == null ? List.of() : response.items();
    }

    @Override
    public List<DownloadCandidate> search(String query) {
        return search(query, List.of());
    }

    @Override
    public List<DownloadCandidate> search(String query, List<String> sources) {
        requireEnabled();
        var response = searchClient.get()
            .uri(builder -> {
                builder.path("/v1/search").queryParam("q", query);
                if (!sources.isEmpty()) {
                    builder.queryParam("sources", String.join(",", sources));
                }
                return builder.build();
            })
            .header("X-Sona-Token", token)
            .accept(MediaType.APPLICATION_JSON)
            .retrieve()
            .body(SearchEnvelope.class);
        return response == null || response.items() == null ? List.of() : response.items();
    }

    @Override
    public List<String> download(String candidateId) {
        requireEnabled();
        var response = downloadClient.post()
            .uri("/v1/downloads")
            .header("X-Sona-Token", token)
            .contentType(MediaType.APPLICATION_JSON)
            .accept(MediaType.APPLICATION_JSON)
            .body(new DownloadBody(candidateId))
            .retrieve()
            .body(DownloadEnvelope.class);
        return response == null || response.files() == null ? List.of() : response.files();
    }

    private RestClient client(String baseUrl, Duration readTimeout) {
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(10));
        requestFactory.setReadTimeout(readTimeout);
        return RestClient.builder()
            .baseUrl(baseUrl)
            .requestFactory(requestFactory)
            .build();
    }

    private void requireEnabled() {
        if (!enabled) {
            throw new IllegalStateException("音乐下载服务未启用");
        }
        if (token == null || token.isBlank()) {
            throw new IllegalStateException("SONA_SIDECAR_TOKEN 未配置");
        }
    }

    private record SourceEnvelope(List<DownloadSource> items) {
    }

    private record SearchEnvelope(List<DownloadCandidate> items) {
    }

    private record DownloadBody(String candidateId) {
    }

    private record DownloadEnvelope(List<String> files) {
    }
}
