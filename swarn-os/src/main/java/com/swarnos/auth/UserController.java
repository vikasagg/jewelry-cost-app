package com.swarnos.auth;

import com.swarnos.common.ApiException;
import com.swarnos.common.AuditService;
import com.swarnos.common.Db;
import java.util.List;
import java.util.Map;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/users")
public class UserController {
    private final Db db;
    private final AuditService audit;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();

    public UserController(Db db, AuditService audit) {
        this.db = db;
        this.audit = audit;
    }

    public record UserRequest(String username, String fullName, String role, String password, Boolean active) {}

    @GetMapping
    public List<Map<String, Object>> list() {
        CurrentUser.require(Permission.USERS);
        return db.rows("SELECT id, username, full_name, role, active, created_at FROM app_user ORDER BY username");
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody UserRequest req) {
        CurrentUser.require(Permission.USERS);
        if (req.username() == null || req.username().isBlank()) throw ApiException.bad("Username is required.");
        if (req.password() == null || req.password().length() < 6) throw ApiException.bad("Password needs at least 6 characters.");
        Role role = parseRole(req.role());
        long id = db.insert("INSERT INTO app_user (username, full_name, password_hash, role) VALUES (?,?,?,?)",
                req.username().trim().toLowerCase(), req.fullName() == null ? req.username() : req.fullName(),
                encoder.encode(req.password()), role.name());
        audit.log("USER_CREATE", "user", id, req.username() + " as " + role);
        return Map.of("id", id);
    }

    @PutMapping("/{id}")
    public Map<String, Object> update(@PathVariable long id, @RequestBody UserRequest req) {
        CurrentUser.require(Permission.USERS);
        db.one("SELECT id FROM app_user WHERE id = ?", "User not found", id);
        if (req.fullName() != null) db.update("UPDATE app_user SET full_name = ? WHERE id = ?", req.fullName(), id);
        if (req.role() != null) db.update("UPDATE app_user SET role = ? WHERE id = ?", parseRole(req.role()).name(), id);
        if (req.active() != null) db.update("UPDATE app_user SET active = ? WHERE id = ?", req.active(), id);
        if (req.password() != null && !req.password().isBlank()) {
            if (req.password().length() < 6) throw ApiException.bad("Password needs at least 6 characters.");
            db.update("UPDATE app_user SET password_hash = ? WHERE id = ?", encoder.encode(req.password()), id);
        }
        audit.log("USER_UPDATE", "user", id, req.role() == null ? null : "role " + req.role());
        return Map.of("id", id);
    }

    private static Role parseRole(String role) {
        try {
            Role r = Role.valueOf(role == null ? "" : role.toUpperCase());
            if (r == Role.PLATFORM) throw new IllegalArgumentException();
            return r;
        } catch (IllegalArgumentException e) {
            throw ApiException.bad("Role must be OWNER, MANAGER, SALES, ACCOUNTANT or STOCK.");
        }
    }
}
