package cc.eu.sosee.sona.library;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.net.URI;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.BAD_REQUEST;

@RestController
@RequestMapping("/api/v1/library/ai-settings")
class AiSettingsController {

    private final AiSettingsRepository repository;

    AiSettingsController(AiSettingsRepository repository) {
        this.repository = repository;
    }

    @GetMapping
    AiSettingsView settings() {
        return repository.view();
    }

    @PutMapping
    AiSettingsView update(@Valid @RequestBody UpdateAiSettingsRequest request) {
        var baseUrl = request.baseUrl().strip();
        var model = request.model().strip();
        var apiKey = request.apiKey() == null || request.apiKey().isBlank()
            ? null : request.apiKey().strip();
        validateBaseUrl(baseUrl);
        if (request.enabled() && apiKey == null && !repository.view().apiKeyConfigured()) {
            throw new ResponseStatusException(BAD_REQUEST, "启用 AI 前请配置 API Key");
        }
        return repository.save(request.enabled(), baseUrl, model, apiKey);
    }

    private void validateBaseUrl(String value) {
        try {
            var uri = URI.create(value);
            var scheme = uri.getScheme();
            if (uri.getHost() == null || uri.getUserInfo() != null
                || !("http".equalsIgnoreCase(scheme) || "https".equalsIgnoreCase(scheme))) {
                throw new IllegalArgumentException();
            }
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(BAD_REQUEST, "AI 服务 URL 无效");
        }
    }

    record UpdateAiSettingsRequest(
        @NotNull Boolean enabled,
        @NotBlank @Size(max = 500) String baseUrl,
        @NotBlank @Size(max = 200) String model,
        @Size(max = 2000) String apiKey
    ) {
    }
}
