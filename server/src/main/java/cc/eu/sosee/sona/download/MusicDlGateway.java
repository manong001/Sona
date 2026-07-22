package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.config.SonaProperties;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;
import java.time.Duration;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

@Component
class MusicDlGateway implements DownloaderGateway {

    private final boolean enabled;
    private final String token;
    private final RestClient searchClient;
    private final RestClient downloadClient;
    private final ObjectMapper objectMapper;

    MusicDlGateway(SonaProperties properties, ObjectMapper objectMapper) {
        var downloader = properties.getDownloader();
        enabled = downloader.isEnabled();
        token = downloader.getToken();
        this.objectMapper = objectMapper;
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
        var requestBody = requestBody(new DownloadBody(candidateId));
        var response = downloadClient.post()
            .uri("/v1/downloads")
            .header("X-Sona-Token", token)
            .contentType(MediaType.APPLICATION_JSON)
            .contentLength(requestBody.length)
            .accept(MediaType.APPLICATION_JSON)
            .body(requestBody)
            .retrieve()
            .body(DownloadEnvelope.class);
        return response == null || response.files() == null ? List.of() : response.files();
    }

    @Override
    public DownloadPlaylistPreview parsePlaylist(String url) {
        requireEnabled();
        try {
            var requestBody = requestBody(new PlaylistBody(url));
            var responseBody = searchClient.post()
                .uri("/v1/playlists/parse")
                .header("X-Sona-Token", token)
                .contentType(MediaType.APPLICATION_JSON)
                .contentLength(requestBody.length)
                .accept(MediaType.APPLICATION_JSON)
                .body(requestBody)
                .retrieve()
                .body(byte[].class);
            var response = responseBody == null || responseBody.length == 0
                ? null
                : objectMapper.readValue(responseBody, DownloadPlaylistPreview.class);
            if (response == null || response.items() == null || response.items().isEmpty()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "歌单中没有可下载歌曲");
            }
            return response;
        } catch (RestClientResponseException exception) {
            var status = exception.getStatusCode().is4xxClientError()
                ? HttpStatus.BAD_REQUEST
                : HttpStatus.BAD_GATEWAY;
            throw new ResponseStatusException(status, playlistError(exception), exception);
        } catch (JacksonException exception) {
            throw new ResponseStatusException(
                HttpStatus.BAD_GATEWAY, "歌单解析服务返回了无效数据", exception
            );
        }
    }

    @Override
    public String resolvePlaybackFallback(String title, String artist, long durationMs, List<String> sources) {
        requireEnabled();
        var requestBody = requestBody(new PlaybackFallbackBody(title, artist, durationMs, sources));
        var response = searchClient.post()
            .uri("/v1/playback/fallbacks")
            .header("X-Sona-Token", token)
            .contentType(MediaType.APPLICATION_JSON)
            .contentLength(requestBody.length)
            .accept(MediaType.APPLICATION_JSON)
            .body(requestBody)
            .retrieve()
            .body(PlaybackFallbackEnvelope.class);
        if (response == null || response.url() == null || response.url().isBlank()) {
            throw new IllegalStateException("在线播放解析服务没有返回链接");
        }
        return response.url();
    }

    private byte[] requestBody(Object value) {
        try {
            return objectMapper.writeValueAsBytes(value);
        } catch (JacksonException exception) {
            throw new IllegalStateException("无法创建下载请求", exception);
        }
    }

    private String playlistError(RestClientResponseException exception) {
        try {
            var response = objectMapper.readValue(exception.getResponseBodyAsString(), ErrorEnvelope.class);
            if (response != null && response.error() != null && !response.error().isBlank()) {
                return response.error();
            }
        } catch (JacksonException ignored) {
            // Fall through to the stable client-facing message.
        }
        return exception.getStatusCode().is4xxClientError()
            ? "歌单链接无法解析"
            : "歌单解析服务暂时不可用";
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

    private record PlaylistBody(String url) {
    }

    private record DownloadEnvelope(List<String> files) {
    }

    private record PlaybackFallbackBody(String title, String artist, long durationMs, List<String> sources) {
    }

    private record PlaybackFallbackEnvelope(String url) {
    }

    private record ErrorEnvelope(String error) {
    }
}
