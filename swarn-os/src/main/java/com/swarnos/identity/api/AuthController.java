package com.swarnos.identity.api;

import com.swarnos.identity.api.dto.LoginRequest;
import com.swarnos.identity.domain.Session;
import com.swarnos.identity.service.AuthService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AuthController {
    private final AuthService auth;

    public AuthController(AuthService auth) {
        this.auth = auth;
    }

    @PostMapping("/api/auth/login")
    public Session login(@RequestBody LoginRequest req) {
        return auth.login(req.shop(), req.username(), req.password());
    }

    @GetMapping("/api/auth/me")
    public Session me() {
        return auth.current();
    }

    @PostMapping("/api/platform/login")
    public Session platformLogin(@RequestBody LoginRequest req) {
        return auth.platformLogin(req.username(), req.password());
    }
}
