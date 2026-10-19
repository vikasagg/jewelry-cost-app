package com.swarnos.auth;

import com.swarnos.common.ApiException;
import com.swarnos.common.AppProperties;
import com.swarnos.common.AuditService;
import com.swarnos.common.Db;
import com.swarnos.tenant.TenantContext;
import com.swarnos.tenant.TenantInfo;
import com.swarnos.tenant.TenantRegistry;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AuthController {
    private final TenantRegistry registry;
    private final TokenService tokens;
    private final Db db;
    private final AuditService audit;
    private final AppProperties props;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();

    public AuthController(TenantRegistry registry, TokenService tokens, Db db, AuditService audit, AppProperties props) {
        this.registry = registry;
        this.tokens = tokens;
        this.db = db;
        this.audit = audit;
        this.props = props;
    }

    public record LoginRequest(String shop, String username, String password) {}

    @PostMapping("/api/auth/login")
    public Map<String, Object> login(@RequestBody LoginRequest req) {
        TenantInfo tenant = registry.find(req.shop() == null ? null : req.shop().trim())
                .orElseThrow(() -> ApiException.forbidden("Wrong shop code, username or password."));
        if (!"ACTIVE".equals(tenant.status())) throw ApiException.forbidden("This shop is not active.");
        return TenantContext.call(tenant.code(), () -> {
            Map<String, Object> u = db.opt("SELECT * FROM app_user WHERE username = ? AND active = TRUE",
                            req.username() == null ? "" : req.username().trim().toLowerCase())
                    .orElseThrow(() -> ApiException.forbidden("Wrong shop code, username or password."));
            if (!encoder.matches(req.password() == null ? "" : req.password(), (String) u.get("password_hash"))) {
                throw ApiException.forbidden("Wrong shop code, username or password.");
            }
            AuthUser user = new AuthUser(tenant.code(), (String) u.get("username"), (String) u.get("full_name"),
                    Role.valueOf((String) u.get("role")));
            CurrentUser.set(user);
            try {
                audit.log("LOGIN", "user", u.get("id"), null);
            } finally {
                CurrentUser.clear();
            }
            return session(user, tenant);
        });
    }

    @GetMapping("/api/auth/me")
    public Map<String, Object> me() {
        AuthUser u = CurrentUser.get();
        return session(u, registry.require(u.tenant()));
    }

    @PostMapping("/api/platform/login")
    public Map<String, Object> platformLogin(@RequestBody LoginRequest req) {
        if (!props.platform().username().equals(req.username()) || !props.platform().password().equals(req.password())) {
            throw ApiException.forbidden("Wrong platform username or password.");
        }
        AuthUser user = new AuthUser("_platform", req.username(), "Platform operator", Role.PLATFORM);
        return Map.of("token", tokens.issue(user), "user", user);
    }

    private Map<String, Object> session(AuthUser user, TenantInfo tenant) {
        Map<String, Object> perms = new LinkedHashMap<>();
        for (Permission p : Permission.values()) perms.put(p.name(), p.allows(user.role()));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("token", tokens.issue(user));
        out.put("user", user);
        out.put("shop", Map.of("code", tenant.code(), "name", tenant.name(), "storageMode", tenant.storageMode()));
        out.put("permissions", perms);
        return out;
    }
}
