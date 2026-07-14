package cc.eu.sosee.sona.library;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class CursorCodecTest {

    private final CursorCodec codec = new CursorCodec();

    @Test
    void roundTripsCursorWithoutExposingRawSortValues() {
        var cursor = new TrackCursor("all about u", "2ac4bd92-0900-4dc3-a4eb-2dc59b18042f");

        var encoded = codec.encode(cursor);

        assertThat(encoded).doesNotContain(cursor.normalizedTitle());
        assertThat(codec.decode(encoded)).isEqualTo(cursor);
    }
}

