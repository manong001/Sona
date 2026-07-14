package cc.eu.sosee.sona.library;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

final class CursorCodec {

    private static final char SEPARATOR = '\0';

    String encode(TrackCursor cursor) {
        var value = cursor.normalizedTitle() + SEPARATOR + cursor.id();
        return Base64.getUrlEncoder().withoutPadding()
            .encodeToString(value.getBytes(StandardCharsets.UTF_8));
    }

    TrackCursor decode(String encoded) {
        try {
            var value = new String(Base64.getUrlDecoder().decode(encoded), StandardCharsets.UTF_8);
            var separatorIndex = value.indexOf(SEPARATOR);
            if (separatorIndex < 0) {
                throw new IllegalArgumentException("Invalid cursor");
            }
            return new TrackCursor(
                value.substring(0, separatorIndex),
                value.substring(separatorIndex + 1)
            );
        } catch (IllegalArgumentException exception) {
            throw new IllegalArgumentException("Invalid cursor", exception);
        }
    }
}

