package cc.eu.sosee.sona.library;

import com.github.houbb.opencc4j.util.ZhConverterUtil;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

final class ArtistNames {

    private static final String LIN_JUNJIE = "林俊杰";
    private static final Map<String, String> ALIASES = Map.of(
        "BIGBANG", "BIGBANG",
        "GDRAGON", "G-DRAGON"
    );
    private static final Map<String, String> DUPLICATE_ALIASES = Map.of(
        "GEM", "邓紫棋",
        "GDTOP", "G-DRAGON"
    );
    private static final Pattern COLLABORATOR_SEPARATOR = Pattern.compile("[,，;；、]");

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

    static String duplicateCanonical(String value) {
        var artist = ZhConverterUtil.toSimple(canonical(value));
        var primaryArtist = COLLABORATOR_SEPARATOR.split(artist, 2)[0].strip();
        if (primaryArtist.contains("邓紫棋")) {
            return "邓紫棋";
        }
        var aliasKey = primaryArtist.replaceAll("[^\\p{L}\\p{N}]+", "")
            .toUpperCase(Locale.ROOT);
        return DUPLICATE_ALIASES.getOrDefault(aliasKey, primaryArtist);
    }
}
