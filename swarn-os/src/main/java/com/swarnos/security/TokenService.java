package com.swarnos.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.swarnos.common.config.AppProperties;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Map;
import java.util.Optional;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.stereotype.Service;

/** Stateless signed login tokens (HMAC-SHA256), so logins survive a server restart. */
@Service
public class TokenService {
    private static final String ALGORITHM = "HmacSHA256";
    private final byte[] secret;
    private final long ttlSeconds;
    private final ObjectMapper json = new ObjectMapper();

    public TokenService(AppProperties props) {
        this.ttlSeconds = props.tokenHours() * 3600L;
        this.secret = loadSecret(props).getBytes(StandardCharsets.UTF_8);
    }

    public String issue(AuthUser user) {
        Map<String, Object> claims = Map.of("t", user.tenant(), "u", user.username(), "n", user.fullName(),
                "r", user.role().name(), "exp", Instant.now().getEpochSecond() + ttlSeconds);
        try {
            String payload = encode(json.writeValueAsBytes(claims));
            return payload + "." + encode(sign(payload));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public Optional<AuthUser> verify(String token) {
        try {
            int dot = token.indexOf('.');
            if (dot < 0) return Optional.empty();
            String payload = token.substring(0, dot);
            if (!MessageDigest.isEqual(Base64.getUrlDecoder().decode(token.substring(dot + 1)), sign(payload))) {
                return Optional.empty();
            }
            Map<?, ?> claims = json.readValue(Base64.getUrlDecoder().decode(payload), Map.class);
            if (((Number) claims.get("exp")).longValue() < Instant.now().getEpochSecond()) return Optional.empty();
            return Optional.of(new AuthUser((String) claims.get("t"), (String) claims.get("u"), (String) claims.get("n"),
                    Role.valueOf((String) claims.get("r"))));
        } catch (IOException | RuntimeException e) {
            return Optional.empty();
        }
    }

    private byte[] sign(String payload) {
        try {
            Mac mac = Mac.getInstance(ALGORITHM);
            mac.init(new SecretKeySpec(secret, ALGORITHM));
            return mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String encode(byte[] bytes) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    /** Configured secret, or one generated once and kept in the data folder. */
    private static String loadSecret(AppProperties props) {
        if (props.tokenSecret() != null && !props.tokenSecret().isBlank()) return props.tokenSecret();
        Path file = Path.of(props.dataDir()).resolve("token.secret");
        try {
            if (!Files.exists(file)) {
                byte[] random = new byte[32];
                new SecureRandom().nextBytes(random);
                Files.createDirectories(file.toAbsolutePath().getParent());
                Files.writeString(file, HexFormat.of().formatHex(random));
            }
            return Files.readString(file).trim();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
