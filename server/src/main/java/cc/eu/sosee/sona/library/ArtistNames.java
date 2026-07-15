package cc.eu.sosee.sona.library;

import java.util.Locale;
import java.util.Map;

final class ArtistNames {

    private static final String LIN_JUNJIE = "林俊杰";
    private static final Map<String, String> ALIASES = Map.of(
        "BIGBANG", "BIGBANG",
        "GDRAGON", "G-DRAGON"
    );

    private ArtistNames() {
    }

    static String canonical(String value) {
        var artist = value == null ? "" : value.strip().replaceAll("\\s+", " ");
        if (artist.contains(LIN_JUNJIE)) {
            return LIN_JUNJIE;
        }
        var aliasKey = artist.replaceAll("[\\s\\p{Pd}_]+", "").toUpperCase(Locale.ROOT);
        return ALIASES.getOrDefault(aliasKey, artist.replaceAll("\\s*([\\p{Pd}])\\s*", "$1"));
    }
}
