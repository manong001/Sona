package cc.eu.sosee.sona.library;

import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

final class LegacyId3TextDecoder {

    private static final Charset GB18030 = Charset.forName("GB18030");
    private static final int MAX_TAG_SIZE = 16 * 1024 * 1024;

    private LegacyId3TextDecoder() {
    }

    static Map<String, String> read(Path path) {
        if (!path.getFileName().toString().toLowerCase(Locale.ROOT).endsWith(".mp3")) {
            return Map.of();
        }
        var values = new HashMap<String, String>();
        try {
            readId3v2(path, values);
            readId3v1(path, values);
        } catch (IOException ignored) {
            return Map.of();
        }
        return values;
    }

    private static void readId3v2(Path path, Map<String, String> values) throws IOException {
        try (var input = Files.newInputStream(path)) {
            var header = input.readNBytes(10);
            if (header.length < 10 || header[0] != 'I' || header[1] != 'D' || header[2] != '3') {
                return;
            }
            var version = header[3] & 0xff;
            if (version != 3 && version != 4) {
                return;
            }
            var size = synchsafe(header, 6);
            if (size <= 0 || size > MAX_TAG_SIZE) {
                return;
            }
            var tag = input.readNBytes(size);
            if (tag.length != size) {
                return;
            }
            if ((header[5] & 0x80) != 0) {
                tag = removeUnsynchronization(tag);
            }
            readFrames(tag, version, (header[5] & 0x40) != 0, values);
        }
    }

    private static void readFrames(
        byte[] tag,
        int version,
        boolean hasExtendedHeader,
        Map<String, String> values
    ) {
        var offset = hasExtendedHeader ? extendedHeaderEnd(tag, version) : 0;
        while (offset + 10 <= tag.length) {
            var id = new String(tag, offset, 4, StandardCharsets.US_ASCII);
            if (!id.matches("[A-Z0-9]{4}")) {
                return;
            }
            var size = version == 4 ? synchsafe(tag, offset + 4) : integer(tag, offset + 4);
            if (size <= 0 || offset + 10L + size > tag.length) {
                return;
            }
            var flags = ((tag[offset + 8] & 0xff) << 8) | (tag[offset + 9] & 0xff);
            if (flags == 0) {
                var key = key(id);
                if (key != null) {
                    var value = decodeText(Arrays.copyOfRange(tag, offset + 10, offset + 10 + size));
                    if (!value.isBlank()) {
                        values.putIfAbsent(key, value);
                    }
                }
            }
            offset += 10 + size;
        }
    }

    private static int extendedHeaderEnd(byte[] tag, int version) {
        if (tag.length < 4) {
            return 0;
        }
        var size = version == 4 ? synchsafe(tag, 0) : integer(tag, 0) + 4;
        return size > 0 && size <= tag.length ? size : 0;
    }

    private static String key(String frameId) {
        return switch (frameId) {
            case "TIT2" -> "title";
            case "TPE1" -> "artist";
            case "TALB" -> "album";
            case "TCON" -> "genre";
            default -> null;
        };
    }

    private static String decodeText(byte[] frame) {
        if (frame.length < 2) {
            return "";
        }
        var encoding = frame[0] & 0xff;
        var content = trimTerminators(Arrays.copyOfRange(frame, 1, frame.length));
        var declared = switch (encoding) {
            case 0 -> StandardCharsets.ISO_8859_1;
            case 1 -> StandardCharsets.UTF_16;
            case 2 -> StandardCharsets.UTF_16BE;
            case 3 -> StandardCharsets.UTF_8;
            default -> null;
        };
        if (declared == null) {
            return "";
        }

        var decoded = decode(content, declared);
        if (decoded == null) {
            decoded = decode(content, GB18030);
        } else if (encoding == 0) {
            var legacy = decode(content, GB18030);
            if (legacy != null && containsCjk(legacy)) {
                decoded = legacy;
            }
        }
        return clean(decoded);
    }

    private static void readId3v1(Path path, Map<String, String> values) throws IOException {
        try (var file = new RandomAccessFile(path.toFile(), "r")) {
            if (file.length() < 128) {
                return;
            }
            var tag = new byte[128];
            file.seek(file.length() - tag.length);
            file.readFully(tag);
            if (tag[0] != 'T' || tag[1] != 'A' || tag[2] != 'G') {
                return;
            }
            putLegacy(values, "title", tag, 3, 30);
            putLegacy(values, "artist", tag, 33, 30);
            putLegacy(values, "album", tag, 63, 30);
        }
    }

    private static void putLegacy(
        Map<String, String> values,
        String key,
        byte[] tag,
        int offset,
        int length
    ) {
        if (values.containsKey(key)) {
            return;
        }
        var content = trimTerminators(Arrays.copyOfRange(tag, offset, offset + length));
        var legacy = decode(content, GB18030);
        if (legacy != null && containsCjk(legacy)) {
            values.put(key, clean(legacy));
        }
    }

    private static String decode(byte[] bytes, Charset charset) {
        try {
            return charset.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString();
        } catch (CharacterCodingException ignored) {
            return null;
        }
    }

    private static byte[] trimTerminators(byte[] bytes) {
        var end = bytes.length;
        while (end > 0 && bytes[end - 1] == 0) {
            end--;
        }
        return end == bytes.length ? bytes : Arrays.copyOf(bytes, end);
    }

    private static String clean(String value) {
        return value == null ? "" : value.replace("\u0000", "").strip();
    }

    private static boolean containsCjk(String value) {
        return value.codePoints().anyMatch(codePoint ->
            Character.UnicodeScript.of(codePoint) == Character.UnicodeScript.HAN
        );
    }

    private static byte[] removeUnsynchronization(byte[] bytes) {
        var output = new byte[bytes.length];
        var length = 0;
        for (var index = 0; index < bytes.length; index++) {
            output[length++] = bytes[index];
            if ((bytes[index] & 0xff) == 0xff
                && index + 1 < bytes.length
                && bytes[index + 1] == 0) {
                index++;
            }
        }
        return Arrays.copyOf(output, length);
    }

    private static int synchsafe(byte[] bytes, int offset) {
        return ((bytes[offset] & 0x7f) << 21)
            | ((bytes[offset + 1] & 0x7f) << 14)
            | ((bytes[offset + 2] & 0x7f) << 7)
            | (bytes[offset + 3] & 0x7f);
    }

    private static int integer(byte[] bytes, int offset) {
        return ((bytes[offset] & 0xff) << 24)
            | ((bytes[offset + 1] & 0xff) << 16)
            | ((bytes[offset + 2] & 0xff) << 8)
            | (bytes[offset + 3] & 0xff);
    }
}
