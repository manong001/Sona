package cc.eu.sosee.sona.library;

final class TrackLanguage {

    private static final int MIN_LYRIC_CHARACTERS = 8;

    private TrackLanguage() {
    }

    static String detect(TrackRecord track) {
        var lyrics = firstText(track.syncedLyrics(), track.plainLyrics());
        var lyricLanguage = dominantLanguage(lyrics, MIN_LYRIC_CHARACTERS, false);
        if (lyricLanguage != null) return lyricLanguage;

        var regionLanguage = switch (track.region()) {
            case "CN" -> "ZH";
            case "KR" -> "KO";
            case "JP" -> "JA";
            case "US" -> "LATIN";
            default -> null;
        };
        if (regionLanguage != null) return regionLanguage;

        var metadata = track.title() + " " + track.artist() + " " + track.album();
        var metadataLanguage = dominantLanguage(metadata, 1, true);
        return metadataLanguage == null ? "UNKNOWN" : metadataLanguage;
    }

    private static String dominantLanguage(String text, int minimum, boolean preferCjk) {
        if (text == null || text.isBlank()) return null;
        var counts = new ScriptCounts();
        text.codePoints().forEach(counts::add);
        if (counts.total() < minimum) return null;
        if (preferCjk) {
            if (counts.hangul > 0) return "KO";
            if (counts.kana > 0) return "JA";
            if (counts.han > 0) return "ZH";
            return counts.latin > 0 ? "LATIN" : null;
        }
        if (counts.hangul > 0) return "KO";
        if (counts.kana > counts.han) return "JA";
        if (counts.han > 0) return "ZH";
        if (counts.kana > 0) return "JA";
        return counts.latin > 0 ? "LATIN" : null;
    }

    private static String firstText(String... values) {
        for (var value : values) {
            if (value != null && !value.isBlank()) return value;
        }
        return null;
    }

    private static final class ScriptCounts {

        private int hangul;
        private int kana;
        private int han;
        private int latin;

        private void add(int codePoint) {
            var script = Character.UnicodeScript.of(codePoint);
            switch (script) {
                case HANGUL -> hangul++;
                case HIRAGANA, KATAKANA -> kana++;
                case HAN -> han++;
                case LATIN -> latin++;
                default -> {
                }
            }
        }

        private int total() {
            return hangul + kana + han + latin;
        }
    }
}
