package cc.eu.sosee.sona.release;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import cc.eu.sosee.sona.config.SonaProperties;
import java.io.ByteArrayOutputStream;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.web.server.ResponseStatusException;

class AppReleaseServiceTest {

    @TempDir
    Path temporaryDirectory;

    @Test
    void publishesAndReloadsUnsignedIpaMetadata() throws Exception {
        var service = service();
        var ipa = new MockMultipartFile(
            "file", "Sona-unsigned.ipa", "application/octet-stream", validIpa()
        );

        var published = service.publish("0.5.0", 6, "目录导入与更新中心", ipa);
        var loaded = service.latest().orElseThrow();

        assertThat(published).isEqualTo(loaded);
        assertThat(loaded.version()).isEqualTo("0.5.0");
        assertThat(loaded.build()).isEqualTo(6);
        assertThat(loaded.notes()).isEqualTo("目录导入与更新中心");
        assertThat(loaded.fileSizeBytes()).isEqualTo(ipa.getSize());
        assertThat(loaded.publishedAt()).isEqualTo(
            Instant.parse("2026-07-15T00:00:00Z").toEpochMilli()
        );
        assertThat(service.packagePath(loaded)).isRegularFile();
    }

    @Test
    void rejectsFilesThatAreNotValidIpaArchives() {
        var invalid = new MockMultipartFile(
            "file", "Sona.ipa", "application/octet-stream", "not-a-zip".getBytes()
        );

        assertThatThrownBy(() -> service().publish("0.5.0", 6, "", invalid))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("IPA");
    }

    private AppReleaseService service() {
        var properties = new SonaProperties();
        properties.setDataDir(temporaryDirectory.resolve("data"));
        return new AppReleaseService(
            properties,
            Clock.fixed(Instant.parse("2026-07-15T00:00:00Z"), ZoneOffset.UTC)
        );
    }

    private byte[] validIpa() throws Exception {
        var output = new ByteArrayOutputStream();
        try (var zip = new ZipOutputStream(output)) {
            zip.putNextEntry(new ZipEntry("Payload/Sona.app/Info.plist"));
            zip.write("plist".getBytes());
            zip.closeEntry();
        }
        return output.toByteArray();
    }
}
