package cc.eu.sosee.sona.library;

import cc.eu.sosee.sona.config.SonaProperties;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.Set;
import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.stereotype.Component;

@Component
class AiSecretCipher {

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final int IV_LENGTH = 12;
    private final Path keyPath;
    private SecretKey key;

    AiSecretCipher(SonaProperties properties) {
        keyPath = properties.getDataDir().toAbsolutePath().normalize().resolve("ai-settings.key");
    }

    String encrypt(String plaintext) {
        try {
            var iv = new byte[IV_LENGTH];
            RANDOM.nextBytes(iv);
            var cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key(), new GCMParameterSpec(128, iv));
            var encrypted = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));
            var payload = new byte[iv.length + encrypted.length];
            System.arraycopy(iv, 0, payload, 0, iv.length);
            System.arraycopy(encrypted, 0, payload, iv.length, encrypted.length);
            return "v1:" + Base64.getEncoder().encodeToString(payload);
        } catch (Exception exception) {
            throw new IllegalStateException("无法加密 AI API Key", exception);
        }
    }

    String decrypt(String ciphertext) {
        if (ciphertext == null || ciphertext.isBlank()) {
            return "";
        }
        if (!ciphertext.startsWith("v1:")) {
            throw new IllegalStateException("无法识别 AI API Key 加密格式");
        }
        try {
            var payload = Base64.getDecoder().decode(ciphertext.substring(3));
            var cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(
                Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, payload, 0, IV_LENGTH)
            );
            return new String(
                cipher.doFinal(payload, IV_LENGTH, payload.length - IV_LENGTH),
                StandardCharsets.UTF_8
            );
        } catch (Exception exception) {
            throw new IllegalStateException("无法解密 AI API Key", exception);
        }
    }

    private synchronized SecretKey key() throws Exception {
        if (key != null) {
            return key;
        }
        Files.createDirectories(keyPath.getParent());
        if (!Files.exists(keyPath)) {
            var bytes = new byte[32];
            RANDOM.nextBytes(bytes);
            Files.writeString(
                keyPath, Base64.getEncoder().encodeToString(bytes),
                StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE
            );
            restrictPermissions();
        }
        var bytes = Base64.getDecoder().decode(Files.readString(keyPath).strip());
        if (bytes.length != 32) {
            throw new IllegalStateException("AI 配置密钥文件无效");
        }
        key = new SecretKeySpec(bytes, "AES");
        return key;
    }

    private void restrictPermissions() {
        try {
            Files.setPosixFilePermissions(keyPath, Set.of(
                java.nio.file.attribute.PosixFilePermission.OWNER_READ,
                java.nio.file.attribute.PosixFilePermission.OWNER_WRITE
            ));
        } catch (Exception ignored) {
            // 非 POSIX 文件系统继续依赖数据目录权限。
        }
    }
}
