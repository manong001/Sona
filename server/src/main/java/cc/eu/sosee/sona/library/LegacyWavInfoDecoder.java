package cc.eu.sosee.sona.library;

import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

final class LegacyWavInfoDecoder {

    private static final Charset GB18030 = Charset.forName("GB18030");
    private static final int MAX_TEXT_SIZE = 1024 * 1024;

    private LegacyWavInfoDecoder() {
    }

    static Map<String, String> read(Path path) {
        if (!path.getFileName().toString().toLowerCase(Locale.ROOT).endsWith(".wav")) {
            return Map.of();
        }
        var values = new HashMap<String, String>();
        try (var file = new RandomAccessFile(path.toFile(), "r")) {
            if (file.length() < 12 || !"RIFF".equals(readFourCc(file))
                || readUnsignedIntLittleEndian(file) < 4 || !"WAVE".equals(readFourCc(file))) {
                return Map.of();
            }
            readChunks(file, values);
        } catch (IOException ignored) {
            return Map.of();
        }
        return values;
    }

    private static void readChunks(
        RandomAccessFile file, Map<String, String> values
    ) throws IOException {
        var offset = 12L;
        while (offset + 8 <= file.length()) {
            file.seek(offset);
            var id = readFourCc(file);
            var size = readUnsignedIntLittleEndian(file);
            var dataStart = offset + 8;
            var dataEnd = dataStart + size;
            if (size < 0 || dataEnd < dataStart || dataEnd > file.length()) {
                return;
            }
            if ("LIST".equals(id) && size >= 4) {
                file.seek(dataStart);
                if ("INFO".equals(readFourCc(file))) {
                    readInfoChunks(file, dataStart + 4, dataEnd, values);
                }
            }
            offset = dataEnd + (size & 1);
        }
    }

    private static void readInfoChunks(
        RandomAccessFile file, long offset, long listEnd, Map<String, String> values
    ) throws IOException {
        while (offset + 8 <= listEnd) {
            file.seek(offset);
            var id = readFourCc(file);
            var size = readUnsignedIntLittleEndian(file);
            var dataStart = offset + 8;
            var dataEnd = dataStart + size;
            if (size < 0 || dataEnd < dataStart || dataEnd > listEnd) {
                return;
            }
            var key = key(id);
            if (key != null && size <= MAX_TEXT_SIZE) {
                var bytes = new byte[(int) size];
                file.readFully(bytes);
                var value = decodeText(bytes);
                if (!value.isBlank()) {
                    values.putIfAbsent(key, value);
                }
            }
            offset = dataEnd + (size & 1);
        }
    }

    private static String key(String chunkId) {
        return switch (chunkId) {
            case "INAM" -> "title";
            case "IART" -> "artist";
            case "IPRD" -> "album";
            case "IGNR" -> "genre";
            default -> null;
        };
    }

    private static String decodeText(byte[] bytes) {
        var length = bytes.length;
        while (length > 0 && bytes[length - 1] == 0) {
            length--;
        }
        var content = ByteBuffer.wrap(bytes, 0, length);
        var decoded = decode(content, StandardCharsets.UTF_8);
        if (decoded == null) {
            content.rewind();
            decoded = decode(content, GB18030);
        }
        return decoded == null ? "" : decoded.replace("\u0000", "").strip();
    }

    private static String decode(ByteBuffer bytes, Charset charset) {
        try {
            return charset.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(bytes)
                .toString();
        } catch (CharacterCodingException ignored) {
            return null;
        }
    }

    private static String readFourCc(RandomAccessFile file) throws IOException {
        var bytes = new byte[4];
        file.readFully(bytes);
        return new String(bytes, StandardCharsets.US_ASCII);
    }

    private static long readUnsignedIntLittleEndian(RandomAccessFile file) throws IOException {
        return Integer.toUnsignedLong(Integer.reverseBytes(file.readInt()));
    }
}
