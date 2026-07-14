package cc.eu.sosee.sona.library;

import java.text.Normalizer;
import java.util.Locale;

final class TextNormalizer {

    private TextNormalizer() {
    }

    static String sortKey(String value) {
        return Normalizer.normalize(value == null ? "" : value, Normalizer.Form.NFKC)
            .strip()
            .toLowerCase(Locale.ROOT);
    }
}

