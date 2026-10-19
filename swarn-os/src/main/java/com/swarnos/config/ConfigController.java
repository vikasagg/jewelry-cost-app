package com.swarnos.config;

import com.swarnos.auth.CurrentUser;
import com.swarnos.auth.Permission;
import com.swarnos.common.ApiException;
import com.swarnos.common.AuditService;
import com.swarnos.common.Db;
import com.swarnos.common.Num;
import java.util.List;
import java.util.Map;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class ConfigController {
    private final ConfigService config;
    private final Db db;
    private final AuditService audit;

    public ConfigController(ConfigService config, Db db, AuditService audit) {
        this.config = config;
        this.db = db;
        this.audit = audit;
    }

    @GetMapping("/config")
    public List<Map<String, Object>> all() {
        return config.all();
    }

    @PutMapping("/config")
    @Transactional
    public Map<String, Object> update(@RequestBody Map<String, String> values) {
        CurrentUser.require(Permission.CONFIG);
        values.forEach(config::set);
        return Map.of("updated", values.size());
    }

    // ---------- masters used by every screen ----------

    @GetMapping("/masters")
    public Map<String, Object> masters() {
        return Map.of(
                "categories", db.rows("SELECT * FROM category WHERE active = TRUE ORDER BY family, name"),
                "purities", db.rows("SELECT * FROM purity WHERE active = TRUE ORDER BY metal, sort_order"),
                "locations", db.rows("SELECT * FROM location ORDER BY id"));
    }

    @PutMapping("/purities/{id}")
    @Transactional
    public Map<String, Object> updatePurity(@PathVariable long id, @RequestBody Map<String, Object> body) {
        CurrentUser.require(Permission.CONFIG);
        Map<String, Object> p = db.one("SELECT * FROM purity WHERE id = ?", "Purity not found", id);
        var factor = Num.of(body.get("price_factor"));
        if (factor.signum() <= 0 || factor.compareTo(java.math.BigDecimal.valueOf(2)) > 0) {
            throw ApiException.bad("Price factor must be between 0 and 2.");
        }
        db.update("UPDATE purity SET price_factor = ? WHERE id = ?", factor, id);
        audit.log("PURITY_FACTOR", "purity", p.get("metal") + " " + p.get("code"), p.get("price_factor") + " -> " + factor);
        return Map.of("id", id);
    }

    @PostMapping("/categories")
    @Transactional
    public Map<String, Object> saveCategory(@RequestBody Map<String, Object> b) {
        CurrentUser.require(Permission.CONFIG);
        String code = str(b.get("code")).toUpperCase();
        if (code.isBlank() || str(b.get("name")).isBlank()) throw ApiException.bad("Code and name are required.");
        String family = str(b.get("family"));
        String metal = switch (family) {
            case "GOLD", "DIAMOND" -> "GOLD";
            case "PLATINUM" -> "PLATINUM";
            case "SILVER", "SILVER_ORNAMENT" -> "SILVER";
            case "GIFTING" -> null;
            default -> throw ApiException.bad("Unknown family: " + family);
        };
        String pricing = metal == null ? "FIXED" : "METAL";
        Object id = b.get("id");
        if (id == null || str(id).isBlank()) {
            long newId = db.insert("""
                    INSERT INTO category (code, name, family, metal, pricing_mode, tracking, tag_type, making_type,
                                          making_value, wastage_pct, gst_pct) VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
                    code, str(b.get("name")), family, metal, pricing,
                    str(b.get("tracking")).isBlank() ? "PIECE" : str(b.get("tracking")), "QR",
                    str(b.get("making_type")).isBlank() ? "PER_GRAM" : str(b.get("making_type")),
                    Num.of(b.get("making_value")), Num.of(b.get("wastage_pct")),
                    b.get("gst_pct") == null ? Num.of(3) : Num.of(b.get("gst_pct")));
            audit.log("CATEGORY_CREATE", "category", code, null);
            return Map.of("id", newId);
        }
        db.update("""
                UPDATE category SET name = ?, making_type = ?, making_value = ?, wastage_pct = ?, gst_pct = ?, active = ?
                WHERE id = ?""", str(b.get("name")), str(b.get("making_type")), Num.of(b.get("making_value")),
                Num.of(b.get("wastage_pct")), Num.of(b.get("gst_pct")), !Boolean.FALSE.equals(b.get("active")),
                Long.parseLong(str(id)));
        audit.log("CATEGORY_UPDATE", "category", code, null);
        return Map.of("id", id);
    }

    @GetMapping("/audit")
    public List<Map<String, Object>> auditLog() {
        CurrentUser.require(Permission.CONFIG);
        return db.rows("SELECT * FROM audit_log ORDER BY id DESC LIMIT 300");
    }

    static String str(Object o) {
        return o == null ? "" : o.toString().trim();
    }
}
