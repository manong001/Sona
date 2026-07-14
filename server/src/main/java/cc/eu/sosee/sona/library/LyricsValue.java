package cc.eu.sosee.sona.library;

import java.util.regex.Pattern;

record LyricsValue(String plain, String synced, String source) {

    private static final Pattern TIMESTAMP = Pattern.compile("(?m)^\\[\\d{1,2}:\\d{2}(?:[.:]\\d{1,3})?]");

    static LyricsValue embedded(String value) {
        if (value == null || value.isBlank()) {
            return new LyricsValue(null, null, null);
        }
        var normalized = value.strip();
        if (TIMESTAMP.matcher(normalized).find()) {
            return new LyricsValue(null, normalized, "EMBEDDED");
        }
        return new LyricsValue(normalized, null, "EMBEDDED");
    }

    LyricsValue withSidecar(String sidecar) {
        if (sidecar == null || sidecar.isBlank() || synced != null) {
            return this;
        }
        var normalized = sidecar.strip();
        if (TIMESTAMP.matcher(normalized).find()) {
            return new LyricsValue(plain, normalized, "SIDECAR");
        }
        return plain == null
            ? new LyricsValue(normalized, null, "SIDECAR")
            : this;
    }
}

