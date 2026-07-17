package cc.eu.sosee.sona.library;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import static org.springframework.http.HttpStatus.BAD_GATEWAY;
import static org.springframework.http.HttpStatus.SERVICE_UNAVAILABLE;

@Component
class OpenAiCompatibleClient {

    private static final String SYSTEM_PROMPT = """
        你是音乐元数据整理助手。根据歌曲标题、艺人、专辑和现有曲风，完成：
        1. 修复标题中的文件序号、扩展名、多余空白和不规范分隔符；不得凭空改写正式歌名；
        2. 给出一个不超过 40 字的主曲风；
        3. 给出最多 5 个不重复的关联曲风，不要重复主曲风；
        4. 用一句中文说明修改依据。
        只返回 JSON 对象，字段必须为 correctedTitle、primaryGenre、relatedGenres、reason。
        """;

    private final AiSettingsRepository settingsRepository;
    private final ObjectMapper objectMapper;

    OpenAiCompatibleClient(AiSettingsRepository settingsRepository, ObjectMapper objectMapper) {
        this.settingsRepository = settingsRepository;
        this.objectMapper = objectMapper;
    }

    private RestClient client(AiRuntimeSettings settings) {
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(settings.timeout());
        requestFactory.setReadTimeout(settings.timeout());
        return RestClient.builder()
            .baseUrl(trimTrailingSlash(settings.baseUrl()))
            .requestFactory(requestFactory)
            .build();
    }

    AiMetadataSuggestion analyze(TrackAiInput input) {
        var settings = requireConfigured();
        try {
            var request = Map.of(
                "model", settings.model(),
                "messages", List.of(
                    Map.of("role", "system", "content", SYSTEM_PROMPT),
                    Map.of("role", "user", "content", objectMapper.writeValueAsString(input))
                ),
                "response_format", Map.of("type", "json_object")
            );
            var response = client(settings).post()
                .uri("/chat/completions")
                .header("Authorization", "Bearer " + settings.apiKey())
                .contentType(MediaType.APPLICATION_JSON)
                .accept(MediaType.APPLICATION_JSON)
                .body(objectMapper.writeValueAsBytes(request))
                .retrieve()
                .body(String.class);
            return parse(response);
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new ResponseStatusException(BAD_GATEWAY, "AI 分析服务调用失败", exception);
        }
    }

    private AiMetadataSuggestion parse(String response) throws JacksonException {
        if (response == null || response.isBlank()) {
            throw new ResponseStatusException(BAD_GATEWAY, "AI 分析服务未返回内容");
        }
        var root = objectMapper.readTree(response);
        var content = root.path("choices").path(0).path("message").path("content").asString("");
        if (content.isBlank()) {
            throw new ResponseStatusException(BAD_GATEWAY, "AI 分析服务返回格式错误");
        }
        JsonNode value = objectMapper.readTree(stripCodeFence(content));
        var title = required(value, "correctedTitle", 200);
        var primaryGenre = required(value, "primaryGenre", 40);
        var relatedGenres = new LinkedHashSet<String>();
        var genresNode = value.path("relatedGenres");
        if (genresNode.isArray()) {
            for (var genreNode : genresNode) {
                var genre = genreNode.asString("").strip();
                if (!genre.isEmpty() && genre.length() <= 40 && !genre.equals(primaryGenre)) {
                    relatedGenres.add(genre);
                }
                if (relatedGenres.size() == 5) {
                    break;
                }
            }
        }
        return new AiMetadataSuggestion(
            title, primaryGenre, List.copyOf(relatedGenres), optional(value, "reason", 500)
        );
    }

    private String required(JsonNode value, String field, int maximumLength) {
        var result = value.path(field).asString("").strip();
        if (result.isEmpty() || result.length() > maximumLength) {
            throw new ResponseStatusException(BAD_GATEWAY, "AI 分析服务返回格式错误");
        }
        return result;
    }

    private String optional(JsonNode value, String field, int maximumLength) {
        var result = value.path(field).asString("").strip();
        return result.length() <= maximumLength ? result : result.substring(0, maximumLength);
    }

    private AiRuntimeSettings requireConfigured() {
        var settings = settingsRepository.runtime();
        if (!settings.configured()) {
            throw new ResponseStatusException(SERVICE_UNAVAILABLE, "AI 功能尚未配置");
        }
        return settings;
    }

    private static String stripCodeFence(String content) {
        var result = content.strip();
        if (result.startsWith("```")) {
            var firstNewline = result.indexOf('\n');
            var lastFence = result.lastIndexOf("```");
            if (firstNewline >= 0 && lastFence > firstNewline) {
                result = result.substring(firstNewline + 1, lastFence).strip();
            }
        }
        return result;
    }

    private static String trimTrailingSlash(String value) {
        var result = value == null || value.isBlank() ? "https://api.openai.com/v1" : value.strip();
        while (result.endsWith("/")) {
            result = result.substring(0, result.length() - 1);
        }
        return result;
    }
}
