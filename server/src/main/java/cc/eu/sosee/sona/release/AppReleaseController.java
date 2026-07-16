package cc.eu.sosee.sona.release;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import org.springframework.core.io.FileSystemResource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/v1/app/releases")
class AppReleaseController {

    private final AppReleaseService service;

    AppReleaseController(AppReleaseService service) {
        this.service = service;
    }

    @GetMapping("/latest")
    AppReleaseResponse latest(@RequestParam(defaultValue = "ios") String platform) {
        var target = AppReleasePlatform.from(platform);
        return service.latest(target)
            .map(release -> AppReleaseResponse.available(release, target))
            .orElseGet(AppReleaseResponse::unavailable);
    }

    @GetMapping("/latest/{extension:ipa|dmg}")
    ResponseEntity<FileSystemResource> download(@PathVariable String extension) throws IOException {
        var platform = AppReleasePlatform.fromExtension(extension);
        var release = service.latest(platform).orElseThrow(() -> new org.springframework.web.server.ResponseStatusException(
            HttpStatus.NOT_FOUND,
            "服务器暂无 " + platform.packageLabel() + " 安装包"
        ));
        var path = service.packagePath(release);
        var downloadName = "Sona-" + release.version() + "-" + release.build()
            + (platform == AppReleasePlatform.IOS ? "-unsigned.ipa" : "-arm64.dmg");
        return ResponseEntity.ok()
            .contentType(MediaType.APPLICATION_OCTET_STREAM)
            .contentLength(Files.size(path))
            .header(
                HttpHeaders.CONTENT_DISPOSITION,
                ContentDisposition.attachment()
                    .filename(downloadName, StandardCharsets.UTF_8)
                    .build()
                    .toString()
            )
            .body(new FileSystemResource(path));
    }

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    ResponseEntity<AppReleaseResponse> publish(
        @RequestParam String version,
        @RequestParam int build,
        @RequestParam(defaultValue = "ios") String platform,
        @RequestParam(defaultValue = "") String notes,
        @RequestPart("file") MultipartFile file
    ) {
        var target = AppReleasePlatform.from(platform);
        var release = service.publish(version, build, notes, file, target);
        return ResponseEntity.status(HttpStatus.CREATED).body(AppReleaseResponse.available(release, target));
    }

    record AppReleaseResponse(
        boolean available,
        String version,
        Integer build,
        String notes,
        Long publishedAt,
        Long fileSizeBytes,
        String fileName,
        String downloadURL
    ) {
        static AppReleaseResponse available(AppRelease release, AppReleasePlatform platform) {
            return new AppReleaseResponse(
                true,
                release.version(),
                release.build(),
                release.notes(),
                release.publishedAt(),
                release.fileSizeBytes(),
                release.fileName(),
                "/api/v1/app/releases/latest/" + platform.fileExtension()
            );
        }

        static AppReleaseResponse unavailable() {
            return new AppReleaseResponse(false, null, null, null, null, null, null, null);
        }
    }
}
