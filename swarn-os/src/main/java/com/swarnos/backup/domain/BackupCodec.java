package com.swarnos.backup.domain;

import com.swarnos.common.error.BusinessException;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;
import javax.crypto.AEADBadTagException;
import javax.crypto.Cipher;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Backup file format: "SWARNOS1" | salt(16) | iv(12) | AES-256-GCM(gzip(content)).
 * The key comes from the password (PBKDF2-HMAC-SHA256, 120,000 rounds).
 */
public final class BackupCodec {
    public static final String EXTENSION = ".swarn";
    public static final int MIN_PASSWORD = 6;
    private static final byte[] MAGIC = "SWARNOS1".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
    private static final int SALT = 16, IV = 12, TAG_BITS = 128, ROUNDS = 120_000;

    private BackupCodec() {}

    public static byte[] encrypt(byte[] plain, String password) {
        checkPassword(password);
        try {
            SecureRandom random = new SecureRandom();
            byte[] salt = new byte[SALT], iv = new byte[IV];
            random.nextBytes(salt);
            random.nextBytes(iv);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key(password, salt), new GCMParameterSpec(TAG_BITS, iv));
            byte[] body = cipher.doFinal(gzip(plain));
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            out.write(MAGIC);
            out.write(salt);
            out.write(iv);
            out.write(body);
            return out.toByteArray();
        } catch (GeneralSecurityException | IOException e) {
            throw new IllegalStateException("Could not encrypt the backup", e);
        }
    }

    public static byte[] decrypt(byte[] file, String password) {
        int header = MAGIC.length + SALT + IV;
        if (file.length < header || !Arrays.equals(Arrays.copyOf(file, MAGIC.length), MAGIC)) {
            throw BusinessException.validation("This is not a Swarn-OS backup file.");
        }
        try {
            byte[] salt = Arrays.copyOfRange(file, MAGIC.length, MAGIC.length + SALT);
            byte[] iv = Arrays.copyOfRange(file, MAGIC.length + SALT, header);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(password == null ? "" : password, salt), new GCMParameterSpec(TAG_BITS, iv));
            return gunzip(cipher.doFinal(file, header, file.length - header));
        } catch (AEADBadTagException e) {
            throw BusinessException.validation("Wrong backup password, or the file is damaged.");
        } catch (GeneralSecurityException | IOException e) {
            throw BusinessException.validation("Could not read the backup: " + e.getMessage());
        }
    }

    public static String sha256(byte[] data) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    public static void checkPassword(String password) {
        if (password == null || password.length() < MIN_PASSWORD) {
            throw BusinessException.validation("Backup password must have at least " + MIN_PASSWORD + " characters.");
        }
    }

    private static SecretKeySpec key(String password, byte[] salt) throws GeneralSecurityException {
        byte[] k = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                .generateSecret(new PBEKeySpec(password.toCharArray(), salt, ROUNDS, 256)).getEncoded();
        return new SecretKeySpec(k, "AES");
    }

    private static byte[] gzip(byte[] data) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (GZIPOutputStream gz = new GZIPOutputStream(out)) {
            gz.write(data);
        }
        return out.toByteArray();
    }

    private static byte[] gunzip(byte[] data) throws IOException {
        try (GZIPInputStream gz = new GZIPInputStream(new ByteArrayInputStream(data))) {
            return gz.readAllBytes();
        }
    }
}
