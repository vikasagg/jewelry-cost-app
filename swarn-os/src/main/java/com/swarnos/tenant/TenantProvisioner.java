package com.swarnos.tenant;

import com.swarnos.common.ApiException;
import com.swarnos.common.AppProperties;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.output.MigrateResult;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;

/**
 * Creates a separate database for each new shop and keeps every shop's schema
 * migrated (BRD FR-TEN-01, FR-TEN-03, FR-TEN-04).
 */
@Service
public class TenantProvisioner {
    private static final Logger log = LoggerFactory.getLogger(TenantProvisioner.class);
    private static final Pattern CODE = Pattern.compile("[a-z][a-z0-9]{1,19}");

    private final TenantRegistry registry;
    private final AppProperties props;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();

    public TenantProvisioner(TenantRegistry registry, AppProperties props) {
        this.registry = registry;
        this.props = props;
    }

    public record NewTenant(String code, String name, String storageMode,
                            String ownerUsername, String ownerName, String ownerPassword) {}

    public TenantInfo create(NewTenant req) {
        String code = req.code() == null ? "" : req.code().trim().toLowerCase();
        if (!CODE.matcher(code).matches()) {
            throw ApiException.bad("Shop code must be 2-20 letters/digits starting with a letter.");
        }
        if (registry.find(code).isPresent()) throw ApiException.conflict("Shop code already in use: " + code);
        if (req.name() == null || req.name().isBlank()) throw ApiException.bad("Shop name is required.");
        if (req.ownerPassword() == null || req.ownerPassword().length() < 6) {
            throw ApiException.bad("Owner password must have at least 6 characters.");
        }
        String mode = req.storageMode() == null ? "LOCAL" : req.storageMode().toUpperCase();

        TenantInfo info;
        if (mode.equals("LOCAL")) {
            info = new TenantInfo(code, req.name().trim(), mode,
                    TenantRegistry.H2_PREFIX + "tenants/" + code + "/" + code, "sa", "", "ACTIVE", null);
        } else if (mode.equals("CLOUD")) {
            info = createPostgresDatabase(code, req.name().trim());
        } else {
            throw ApiException.bad("Storage mode must be LOCAL or CLOUD.");
        }

        registry.insert(info);
        try {
            migrate(code);
            JdbcTemplate jdbc = new JdbcTemplate(registry.dataSource(code));
            jdbc.update("INSERT INTO app_user (username, full_name, password_hash, role) VALUES (?,?,?,'OWNER')",
                    blankTo(req.ownerUsername(), "owner").toLowerCase(), blankTo(req.ownerName(), "Owner"),
                    encoder.encode(req.ownerPassword()));
            jdbc.update("UPDATE app_config SET config_value = ? WHERE config_key = 'shop.name'", info.name());
        } catch (RuntimeException e) {
            registry.closePool(code);
            registry.delete(code);
            throw e;
        }
        log.info("Created shop {} ({}, {})", code, info.name(), mode);
        return registry.require(code);
    }

    private TenantInfo createPostgresDatabase(String code, String name) {
        AppProperties.CloudPostgres pg = props.cloudPostgres();
        String dbName = pg.databasePrefix() + code;
        String adminUrl = "jdbc:postgresql://" + pg.host() + ":" + pg.port() + "/postgres";
        try (Connection c = DriverManager.getConnection(adminUrl, pg.username(), pg.password());
             Statement st = c.createStatement()) {
            st.execute("CREATE DATABASE " + dbName);   // code is validated against [a-z0-9]
        } catch (Exception e) {
            throw ApiException.bad("Could not create the cloud database: " + e.getMessage());
        }
        String url = "jdbc:postgresql://" + pg.host() + ":" + pg.port() + "/" + dbName;
        return new TenantInfo(code, name, "CLOUD", url, pg.username(), pg.password(), "ACTIVE", null);
    }

    public String migrate(String code) {
        MigrateResult result = Flyway.configure()
                .dataSource(registry.dataSource(code))
                .locations("classpath:db/tenant")
                .load()
                .migrate();
        String version = result.targetSchemaVersion != null ? result.targetSchemaVersion : result.initialSchemaVersion;
        registry.setSchemaVersion(code, version);
        return version;
    }

    /** Upgrades every shop; one failing shop does not stop the others. Returns the failures. */
    public List<String> migrateAll() {
        List<String> failed = new ArrayList<>();
        for (TenantInfo t : registry.list()) {
            try {
                migrate(t.code());
            } catch (Exception e) {
                log.error("Migration failed for shop {}", t.code(), e);
                failed.add(t.code() + ": " + e.getMessage());
            }
        }
        return failed;
    }

    private static String blankTo(String s, String fallback) {
        return s == null || s.isBlank() ? fallback : s.trim();
    }
}
