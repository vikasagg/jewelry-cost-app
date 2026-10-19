package com.swarnos.tenant.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.tenant.domain.StorageMode;
import com.swarnos.tenant.domain.Tenant;
import com.swarnos.tenant.domain.TenantStatus;
import com.swarnos.tenant.infrastructure.ControlDatabaseConfig;
import java.util.List;
import java.util.Optional;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Shop registry in the control database. */
@Repository
public class TenantRepository {
    private static final RowMapper<Tenant> MAPPER = (rs, i) -> new Tenant(rs.getString("code"), rs.getString("name"),
            StorageMode.valueOf(rs.getString("storage_mode")), rs.getString("jdbc_url"), rs.getString("db_username"),
            rs.getString("db_password"), TenantStatus.valueOf(rs.getString("status")), rs.getString("schema_version"),
            Columns.instant(rs, "created_at"));

    private final JdbcClient jdbc;

    public TenantRepository(@Qualifier(ControlDatabaseConfig.CONTROL) JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public List<Tenant> findAll() {
        return jdbc.sql("SELECT * FROM tenant ORDER BY created_at").query(MAPPER).list();
    }

    public Optional<Tenant> findByCode(String code) {
        return jdbc.sql("SELECT * FROM tenant WHERE code = ?").params(code).query(MAPPER).optional();
    }

    public void insert(Tenant t) {
        jdbc.sql("""
                INSERT INTO tenant (code, name, storage_mode, jdbc_url, db_username, db_password, status)
                VALUES (?,?,?,?,?,?,?)""")
                .params(t.code(), t.name(), t.storageMode().name(), t.jdbcUrl(), t.dbUsername(), t.dbPassword(), t.status().name())
                .update();
    }

    public void delete(String code) {
        jdbc.sql("DELETE FROM tenant WHERE code = ?").params(code).update();
    }

    public void updateStatus(String code, TenantStatus status) {
        jdbc.sql("UPDATE tenant SET status = ? WHERE code = ?").params(status.name(), code).update();
    }

    public void updateSchemaVersion(String code, String version) {
        jdbc.sql("UPDATE tenant SET schema_version = ? WHERE code = ?").params(version, code).update();
    }
}
