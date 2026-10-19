package com.swarnos.identity.service;

import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.config.AppProperties;
import com.swarnos.common.error.BusinessException;
import com.swarnos.identity.domain.Session;
import com.swarnos.identity.domain.User;
import com.swarnos.identity.repository.UserRepository;
import com.swarnos.security.AuthUser;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.security.Role;
import com.swarnos.security.TokenService;
import com.swarnos.tenant.domain.Tenant;
import com.swarnos.tenant.infrastructure.TenantContext;
import com.swarnos.tenant.service.TenantService;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

/** Shop staff and platform operator sign-in. */
@Service
public class AuthService {
    private static final String WRONG = "Wrong shop code, username or password.";

    private final TenantService tenants;
    private final UserRepository users;
    private final TokenService tokens;
    private final PasswordEncoder encoder;
    private final AuditService audit;
    private final AppProperties props;

    public AuthService(TenantService tenants, UserRepository users, TokenService tokens, PasswordEncoder encoder,
                       AuditService audit, AppProperties props) {
        this.tenants = tenants;
        this.users = users;
        this.tokens = tokens;
        this.encoder = encoder;
        this.audit = audit;
        this.props = props;
    }

    public Session login(String shop, String username, String password) {
        Tenant tenant = tenants.find(shop).orElseThrow(() -> BusinessException.forbidden(WRONG));
        if (!tenant.isActive()) throw BusinessException.forbidden("This shop is not active.");
        return TenantContext.call(tenant.code(), () -> {
            User user = users.findActiveByUsername(username == null ? "" : username.trim().toLowerCase())
                    .filter(u -> encoder.matches(password == null ? "" : password, u.passwordHash()))
                    .orElseThrow(() -> BusinessException.forbidden(WRONG));
            AuthUser authUser = new AuthUser(tenant.code(), user.username(), user.fullName(), user.role());
            CurrentUser.runAs(authUser, () -> {
                audit.record("LOGIN", "user", user.id(), null);
                return null;
            });
            return session(authUser, tenant);
        });
    }

    public Session current() {
        AuthUser user = CurrentUser.get();
        return session(user, tenants.require(user.tenant()));
    }

    public Session platformLogin(String username, String password) {
        if (!props.platform().username().equals(username) || !props.platform().password().equals(password)) {
            throw BusinessException.forbidden("Wrong platform username or password.");
        }
        AuthUser user = new AuthUser(AuthUser.PLATFORM_TENANT, username, "Platform operator", Role.PLATFORM);
        return new Session(tokens.issue(user), user, null, Map.of());
    }

    private Session session(AuthUser user, Tenant tenant) {
        Map<String, Boolean> permissions = new LinkedHashMap<>();
        for (Permission p : Permission.values()) permissions.put(p.name(), p.allows(user.role()));
        return new Session(tokens.issue(user), user,
                new Session.ShopInfo(tenant.code(), tenant.name(), tenant.storageMode().name()), permissions);
    }
}
