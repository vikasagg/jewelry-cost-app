package com.swarnos.tenant;

import com.swarnos.common.ApiException;
import com.swarnos.common.AppProperties;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import jakarta.annotation.PreDestroy;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * Control-plane registry: which shops exist and where each shop's own database
 * lives. Holds one connection pool per shop; no query ever crosses shops.
 */
@Component
public class TenantRegistry {
    static final String H2_PREFIX = "h2:";

    private final Path dataDir;
    private final HikariDataSource control;
    private final JdbcClient controlJdbc;
    private final Map<String, HikariDataSource> pools = new ConcurrentHashMap<>();

    public TenantRegistry(AppProperties props) throws Exception {
        this.dataDir = Path.of(props.dataDir()).toAbsolutePath().normalize();
        Files.createDirectories(dataDir.resolve("tenants"));
        String url = props.controlDb() != null && props.controlDb().url() != null && !props.controlDb().url().isBlank()
                ? props.controlDb().url()
                : h2Url(dataDir.resolve("control").toString());
        String user = props.controlDb() == null ? "sa" : props.controlDb().username();
        String pass = props.controlDb() == null ? "" : props.controlDb().password();
        this.control = pool("control", url, user, pass, 4);
        Flyway.configure().dataSource(control).locations("classpath:db/control").load().migrate();
        this.controlJdbc = JdbcClient.create(control);
    }

    public Path dataDir() {
        return dataDir;
    }

    public static String h2Url(String path) {
        return "jdbc:h2:file:" + path + ";MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DEFAULT_NULL_ORDERING=HIGH";
    }

    /** Local tenants are stored as "h2:tenants/<code>/<code>" so the data folder can be moved or copied. */
    String resolveUrl(String stored) {
        if (stored.startsWith(H2_PREFIX)) {
            return h2Url(dataDir.resolve(stored.substring(H2_PREFIX.length())).toString());
        }
        return stored;
    }

    public List<TenantInfo> list() {
        return controlJdbc.sql("SELECT * FROM tenant ORDER BY created_at").query(this::map).list();
    }

    public Optional<TenantInfo> find(String code) {
        if (code == null) return Optional.empty();
        return controlJdbc.sql("SELECT * FROM tenant WHERE code = ?").params(code.toLowerCase())
                .query(this::map).optional();
    }

    public TenantInfo require(String code) {
        return find(code).orElseThrow(() -> ApiException.notFound("Unknown shop code: " + code));
    }

    void insert(TenantInfo t) {
        controlJdbc.sql("""
                INSERT INTO tenant (code, name, storage_mode, jdbc_url, db_username, db_password, status)
                VALUES (?,?,?,?,?,?,?)""")
                .params(t.code(), t.name(), t.storageMode(), t.jdbcUrl(), t.dbUsername(), t.dbPassword(), t.status())
                .update();
    }

    void delete(String code) {
        controlJdbc.sql("DELETE FROM tenant WHERE code = ?").params(code).update();
    }

    void setSchemaVersion(String code, String version) {
        controlJdbc.sql("UPDATE tenant SET schema_version = ? WHERE code = ?").params(version, code).update();
    }

    public void setStatus(String code, String status) {
        controlJdbc.sql("UPDATE tenant SET status = ? WHERE code = ?").params(status, code).update();
    }

    public DataSource dataSource(String code) {
        return pools.computeIfAbsent(code, c -> {
            TenantInfo t = require(c);
            return pool("tenant-" + c, resolveUrl(t.jdbcUrl()), t.dbUsername(), t.dbPassword(), 8);
        });
    }

    void closePool(String code) {
        HikariDataSource ds = pools.remove(code);
        if (ds != null) ds.close();
    }

    private static HikariDataSource pool(String name, String url, String user, String pass, int size) {
        HikariConfig cfg = new HikariConfig();
        cfg.setPoolName(name);
        cfg.setJdbcUrl(url);
        cfg.setUsername(user);
        cfg.setPassword(pass == null ? "" : pass);
        cfg.setMaximumPoolSize(size);
        cfg.setMinimumIdle(0);
        return new HikariDataSource(cfg);
    }

    private TenantInfo map(java.sql.ResultSet rs, int i) throws java.sql.SQLException {
        return new TenantInfo(rs.getString("code"), rs.getString("name"), rs.getString("storage_mode"),
                rs.getString("jdbc_url"), rs.getString("db_username"), rs.getString("db_password"),
                rs.getString("status"), rs.getString("schema_version"));
    }

    @PreDestroy
    void close() {
        pools.values().forEach(HikariDataSource::close);
        control.close();
    }
}
