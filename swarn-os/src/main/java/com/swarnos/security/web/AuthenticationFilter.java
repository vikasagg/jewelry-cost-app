package com.swarnos.security.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.swarnos.common.api.ApiError;
import com.swarnos.security.AuthUser;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Role;
import com.swarnos.security.TokenService;
import com.swarnos.tenant.infrastructure.TenantContext;
import com.swarnos.tenant.service.TenantService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Optional;
import java.util.Set;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Resolves the signed-in user and their shop for every API call, so each
 * request only reaches that shop's own database (BRD FR-TEN-02).
 */
@Component
public class AuthenticationFilter extends OncePerRequestFilter {
    private static final Set<String> PUBLIC = Set.of("/api/auth/login", "/api/platform/login");

    private final TokenService tokens;
    private final TenantService tenants;
    private final ObjectMapper json;

    public AuthenticationFilter(TokenService tokens, TenantService tenants, ObjectMapper json) {
        this.tokens = tokens;
        this.tenants = tenants;
        this.json = json;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest req) {
        String path = req.getRequestURI();
        return !path.startsWith("/api/") || PUBLIC.contains(path);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        Optional<AuthUser> user = Optional.ofNullable(bearerToken(req)).flatMap(tokens::verify);
        if (user.isEmpty()) {
            deny(res, HttpServletResponse.SC_UNAUTHORIZED, "Please sign in again.");
            return;
        }
        AuthUser u = user.get();
        boolean platformPath = req.getRequestURI().startsWith("/api/platform/");
        if (platformPath != (u.role() == Role.PLATFORM)) {
            deny(res, HttpServletResponse.SC_FORBIDDEN, "Not allowed.");
            return;
        }
        if (!platformPath && !tenants.isActive(u.tenant())) {
            deny(res, HttpServletResponse.SC_FORBIDDEN, "This shop is not active.");
            return;
        }
        if (!platformPath) TenantContext.set(u.tenant());
        CurrentUser.set(u);
        try {
            chain.doFilter(req, res);
        } finally {
            CurrentUser.clear();
            TenantContext.clear();
        }
    }

    private static String bearerToken(HttpServletRequest req) {
        String header = req.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) return header.substring(7);
        return req.getParameter("token");   // printable pages and downloads opened in a new tab
    }

    private void deny(HttpServletResponse res, int status, String message) throws IOException {
        res.setStatus(status);
        res.setContentType(MediaType.APPLICATION_JSON_VALUE);
        json.writeValue(res.getOutputStream(), new ApiError(message));
    }
}
