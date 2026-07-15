package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import cc.eu.sosee.sona.config.SonaProperties;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.web.server.ResponseStatusException;

class ServerMusicDirectoryServiceTest {

    @TempDir
    Path temporaryDirectory;

    @Test
    void listsOnlyChildDirectoriesAndKeepsPathsRelativeToMount() throws Exception {
        var musicDirectory = Files.createDirectories(temporaryDirectory.resolve("music"));
        Files.createDirectories(musicDirectory.resolve("华语/林俊杰"));
        Files.createDirectories(musicDirectory.resolve("欧美"));
        Files.writeString(musicDirectory.resolve("根目录歌曲.mp3"), "audio");
        var service = service(musicDirectory);

        var root = service.list("");
        var chinese = service.list("华语");

        assertThat(root.path()).isEmpty();
        assertThat(root.name()).isEqualTo("music");
        assertThat(root.directories()).extracting(ServerMusicDirectory::path)
            .containsExactly("华语", "欧美");
        assertThat(chinese.directories()).containsExactly(
            new ServerMusicDirectory("华语/林俊杰", "林俊杰", false)
        );
    }

    @Test
    void rejectsPathsOutsideMountedMusicDirectory() throws Exception {
        var musicDirectory = Files.createDirectories(temporaryDirectory.resolve("music"));
        Files.createDirectories(temporaryDirectory.resolve("private"));
        var service = service(musicDirectory);

        assertThatThrownBy(() -> service.list("../private"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("400 BAD_REQUEST");
    }

    private ServerMusicDirectoryService service(Path musicDirectory) {
        var properties = new SonaProperties();
        properties.setMusicDir(musicDirectory);
        return new ServerMusicDirectoryService(properties);
    }
}
