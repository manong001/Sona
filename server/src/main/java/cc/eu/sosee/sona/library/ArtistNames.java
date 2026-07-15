package cc.eu.sosee.sona.library;

final class ArtistNames {

    private static final String LIN_JUNJIE = "林俊杰";

    private ArtistNames() {
    }

    static String canonical(String value) {
        var artist = value == null ? "" : value.strip();
        return artist.contains(LIN_JUNJIE) ? LIN_JUNJIE : artist;
    }
}
