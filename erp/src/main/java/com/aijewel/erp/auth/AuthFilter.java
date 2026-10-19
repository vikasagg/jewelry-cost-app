package com.aijewel.erp.auth;

import com.aijewel.erp.tenant.TenantContext;
import com.aijewel.erp.tenant.TenantInfo;
import com.aijewel.erp.tenant.TenantRegistry;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Optional;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Resolves the signed-in user and their shop for every API call, so each
 * request only ever reaches that shop's own database (BRD FR-TEN-02).
 */
@Component
public class AuthFilter extends OncePerRequestFilter {
    private final TokenService tokens;
    private final TenantRegistry registry;

    public AuthFilter(TokenService tokens, TenantRegistry registry) {
        this.tokens = tokens;
        this.registry = registry;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest req) {
        String p = req.getRequestURI();
        return !p.startsWith("/api/") || p.equals("/api/auth/login") || p.equals("/api/platform/login")
                || p.startsWith("/api/public/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        Optional<AuthUser> user = Optional.ofNullable(bearer(req)).flatMap(tokens::verify);
        if (user.isEmpty()) {
            deny(res, 401, "Please sign in again.");
            return;
        }
        AuthUser u = user.get();
        boolean platformPath = req.getRequestURI().startsWith("/api/platform/");
        if (platformPath != (u.role() == Role.PLATFORM)) {
            deny(res, 403, "Not allowed.");
            return;
        }
        if (!platformPath) {
            Optional<TenantInfo> t = registry.find(u.tenant());
            if (t.isEmpty() || !"ACTIVE".equals(t.get().status())) {
                deny(res, 403, "This shop is not active.");
                return;
            }
            TenantContext.set(u.tenant());
        }
        CurrentUser.set(u);
        try {
            chain.doFilter(req, res);
        } finally {
            CurrentUser.clear();
            TenantContext.clear();
        }
    }

    private static String bearer(HttpServletRequest req) {
        String h = req.getHeader("Authorization");
        if (h != null && h.startsWith("Bearer ")) return h.substring(7);
        return req.getParameter("token");   // printable pages and file downloads opened in a new tab
    }

    private static void deny(HttpServletResponse res, int status, String msg) throws IOException {
        res.setStatus(status);
        res.setContentType("application/json");
        res.getWriter().write("{\"error\":\"" + msg + "\"}");
    }
}
