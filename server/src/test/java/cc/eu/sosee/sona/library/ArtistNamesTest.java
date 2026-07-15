package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class ArtistNamesTest {

    @Test
    void keepsNamesWholeAndCanonicalizesEveryArtistContainingLinJunjie() {
        assertThat(ArtistNames.canonical("Taylor Swift feat. Ed Sheeran"))
            .isEqualTo("Taylor Swift feat. Ed Sheeran");
        assertThat(ArtistNames.canonical("阿杜 / 林俊杰 feat. 其他歌手"))
            .isEqualTo("林俊杰");
    }
}
