package com.swarnos.config;

import com.swarnos.auth.CurrentUser;
import com.swarnos.common.ApiException;
import com.swarnos.common.AuditService;
import com.swarnos.common.Db;
import com.swarnos.common.Num;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;

/** Business settings stored in each shop's app_config table (BRD §16). */
@Service
public class ConfigService {
    private final Db db;
    private final AuditService audit;

    public ConfigService(Db db, AuditService audit) {
        this.db = db;
        this.audit = audit;
    }

    public List<Map<String, Object>> all() {
        return db.rows("SELECT * FROM app_config ORDER BY config_key");
    }

    public String get(String key, String fallback) {
        String v = db.value("SELECT config_value FROM app_config WHERE config_key = ?", String.class, key);
        return v == null || v.isBlank() ? fallback : v.trim();
    }

    public BigDecimal decimal(String key, BigDecimal fallback) {
        String v = get(key, null);
        return v == null ? fallback : Num.of(v);
    }

    /** Blank means "no limit" (owner decision D-05). */
    public BigDecimal limit(String key) {
        return Num.ofNullable(get(key, null));
    }

    public boolean flag(String key, boolean fallback) {
        String v = get(key, null);
        return v == null ? fallback : v.equalsIgnoreCase("true");
    }

    public void set(String key, String value) {
        String old = db.value("SELECT config_value FROM app_config WHERE config_key = ?", String.class, key);
        int n = db.update("UPDATE app_config SET config_value = ?, updated_by = ?, updated_at = ? WHERE config_key = ?",
                value, CurrentUser.usernameOrSystem(), Timestamp.from(Instant.now()), key);
        if (n == 0) throw ApiException.notFound("Unknown setting: " + key);
        audit.log("CONFIG_CHANGE", "config", key, old + " -> " + value);
    }
}
