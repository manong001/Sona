package cc.eu.sosee.sona.download;

import cc.eu.sosee.sona.config.SonaProperties;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.URI;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Optional;
import javax.imageio.ImageIO;
import org.springframework.stereotype.Component;

@Component
class FilePlaylistSubscriptionArtworkArchive
    implements PlaylistSubscriptionArtworkArchive {

    private static final int EDGE = 1200;
    private static final int MAX_REDIRECTS = 3;
    private static final int MAX_SOURCE_BYTES = 8 * 1024 * 1024;
    private static final long MAX_PIXELS = 40_000_000L;

    private final Path directory;

    FilePlaylistSubscriptionArtworkArchive(SonaProperties properties) {
        directory = properties.getDataDir()
            .resolve("playlist-subscription-artwork")
            .toAbsolutePath()
            .normalize();
    }

    @Override
    public Optional<String> archive(String sourceUrl) {
        if (sourceUrl == null || sourceUrl.isBlank()) {
            return Optional.empty();
        }
        try {
            return Optional.of(archiveBytes(download(URI.create(sourceUrl.strip()))));
        } catch (IllegalArgumentException | IOException exception) {
            throw new IllegalStateException("无法保存订阅歌单封面", exception);
        }
    }

    @Override
    public byte[] read(String contentHash) {
        if (contentHash == null || !contentHash.matches("[0-9a-f]{64}")) {
            throw new IllegalArgumentException("无效的订阅歌单封面版本");
        }
        try {
            return Files.readAllBytes(path(contentHash));
        } catch (IOException exception) {
            throw new IllegalStateException("订阅歌单封面不存在", exception);
        }
    }

    String archiveBytes(byte[] sourceBytes) throws IOException {
        if (sourceBytes.length == 0 || sourceBytes.length > MAX_SOURCE_BYTES) {
            throw new IOException("订阅歌单封面大小无效");
        }
        var source = ImageIO.read(new ByteArrayInputStream(sourceBytes));
        if (source == null || source.getWidth() <= 0 || source.getHeight() <= 0
            || (long) source.getWidth() * source.getHeight() > MAX_PIXELS) {
            throw new IOException("订阅歌单封面格式无效");
        }
        var encoded = normalize(source);
        var hash = sha256(encoded);
        Files.createDirectories(directory);
        try {
            Files.write(path(hash), encoded, StandardOpenOption.CREATE_NEW);
        } catch (FileAlreadyExistsException ignored) {
            // 内容寻址文件已经存在时直接复用。
        }
        return hash;
    }

    private byte[] download(URI initialUri) throws IOException {
        var uri = initialUri;
        for (var redirect = 0; redirect <= MAX_REDIRECTS; redirect++) {
            validatePublicHttpUri(uri);
            var connection = (HttpURLConnection) uri.toURL().openConnection();
            connection.setConnectTimeout(10_000);
            connection.setReadTimeout(10_000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("Accept", "image/*");
            connection.setRequestProperty("User-Agent", "Sona/playlist-artwork");
            var status = connection.getResponseCode();
            if (status >= 300 && status < 400) {
                var location = connection.getHeaderField("Location");
                connection.disconnect();
                if (location == null || redirect == MAX_REDIRECTS) {
                    throw new IOException("订阅歌单封面重定向无效");
                }
                uri = uri.resolve(location);
                continue;
            }
            if (status < 200 || status >= 300) {
                connection.disconnect();
                throw new IOException("订阅歌单封面响应状态异常: " + status);
            }
            try (var input = connection.getInputStream()) {
                var bytes = input.readNBytes(MAX_SOURCE_BYTES + 1);
                if (bytes.length > MAX_SOURCE_BYTES) {
                    throw new IOException("订阅歌单封面不能超过 8 MB");
                }
                return bytes;
            } finally {
                connection.disconnect();
            }
        }
        throw new IOException("订阅歌单封面重定向过多");
    }

    private void validatePublicHttpUri(URI uri) throws IOException {
        var scheme = uri.getScheme();
        if (scheme == null
            || (!scheme.equalsIgnoreCase("https") && !scheme.equalsIgnoreCase("http"))
            || uri.getHost() == null) {
            throw new IOException("订阅歌单封面地址无效");
        }
        for (var address : InetAddress.getAllByName(uri.getHost())) {
            if (address.isAnyLocalAddress() || address.isLoopbackAddress()
                || address.isLinkLocalAddress() || address.isSiteLocalAddress()
                || address.isMulticastAddress()) {
                throw new IOException("订阅歌单封面地址不可访问");
            }
        }
    }

    private byte[] normalize(BufferedImage source) throws IOException {
        var side = Math.min(source.getWidth(), source.getHeight());
        var x = (source.getWidth() - side) / 2;
        var y = (source.getHeight() - side) / 2;
        var outputSide = Math.min(side, EDGE);
        var output = new BufferedImage(outputSide, outputSide, BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = output.createGraphics();
        graphics.setColor(Color.BLACK);
        graphics.fillRect(0, 0, outputSide, outputSide);
        graphics.setRenderingHint(
            RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC
        );
        graphics.drawImage(
            source, 0, 0, outputSide, outputSide, x, y, x + side, y + side, null
        );
        graphics.dispose();
        var outputBytes = new ByteArrayOutputStream();
        if (!ImageIO.write(output, "jpg", outputBytes)) {
            throw new IOException("JPEG 编码器不可用");
        }
        return outputBytes.toByteArray();
    }

    private String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(bytes)
            );
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException(exception);
        }
    }

    private Path path(String hash) {
        return directory.resolve(hash + ".jpg");
    }
}
