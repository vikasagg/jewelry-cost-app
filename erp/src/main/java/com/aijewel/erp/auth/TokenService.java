package com.aijewel.erp.auth;

import com.aijewel.erp.common.AppProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
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
    private final byte[] secret;
    private final long ttlSeconds;
    private final ObjectMapper json = new ObjectMapper();

    public TokenService(AppProperties props) throws Exception {
        this.ttlSeconds = props.tokenHours() * 3600L;
        if (props.tokenSecret() != null && !props.tokenSecret().isBlank()) {
            this.secret = props.tokenSecret().getBytes(StandardCharsets.UTF_8);
        } else {
            Path file = Path.of(props.dataDir()).resolve("token.secret");
            if (!Files.exists(file)) {
                byte[] random = new byte[32];
                new SecureRandom().nextBytes(random);
                Files.createDirectories(file.getParent());
                Files.writeString(file, HexFormat.of().formatHex(random));
            }
            this.secret = Files.readString(file).trim().getBytes(StandardCharsets.UTF_8);
        }
    }

    public String issue(AuthUser user) {
        try {
            Map<String, Object> body = Map.of("t", user.tenant(), "u", user.username(), "n", user.fullName(),
                    "r", user.role().name(), "exp", Instant.now().getEpochSecond() + ttlSeconds);
            String payload = b64(json.writeValueAsBytes(body));
            return payload + "." + b64(sign(payload));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    public Optional<AuthUser> verify(String token) {
        try {
            int dot = token.indexOf('.');
            if (dot < 0) return Optional.empty();
            String payload = token.substring(0, dot);
            byte[] given = Base64.getUrlDecoder().decode(token.substring(dot + 1));
            if (!MessageDigest.isEqual(given, sign(payload))) return Optional.empty();
            Map<?, ?> body = json.readValue(Base64.getUrlDecoder().decode(payload), Map.class);
            if (((Number) body.get("exp")).longValue() < Instant.now().getEpochSecond()) return Optional.empty();
            return Optional.of(new AuthUser((String) body.get("t"), (String) body.get("u"), (String) body.get("n"),
                    Role.valueOf((String) body.get("r"))));
        } catch (Exception e) {
            return Optional.empty();
        }
    }

    private byte[] sign(String payload) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret, "HmacSHA256"));
        return mac.doFinal(payload.getBytes(StandardCharsets.UTF_8));
    }

    private static String b64(byte[] bytes) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
}
