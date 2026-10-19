package com.swarnos.tenant.infrastructure;

import com.swarnos.common.config.AppProperties;
import com.swarnos.common.error.BusinessException;
import com.swarnos.tenant.domain.StorageMode;
import com.swarnos.tenant.domain.Tenant;
import com.swarnos.tenant.domain.TenantStatus;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.output.MigrateResult;
import org.springframework.stereotype.Component;

/** Creates a shop's own database and applies the shop schema (Flyway, db/tenant). */
@Component
public class TenantDatabaseFactory {
    private final AppProperties props;
    private final TenantDataSources dataSources;

    public TenantDatabaseFactory(AppProperties props, TenantDataSources dataSources) {
        this.props = props;
        this.dataSources = dataSources;
    }

    /** Describes (and for CLOUD, creates) the database of a new shop. The code is already validated. */
    public Tenant newDatabase(String code, String name, StorageMode mode) {
        if (mode == StorageMode.LOCAL) {
            return new Tenant(code, name, mode, Tenant.LOCAL_URL_PREFIX + "tenants/" + code + "/" + code, "sa", "",
                    TenantStatus.ACTIVE, null, null);
        }
        AppProperties.CloudPostgres pg = props.cloudPostgres();
        String database = pg.databasePrefix() + code;
        String server = "jdbc:postgresql://" + pg.host() + ":" + pg.port() + "/";
        try (Connection c = DriverManager.getConnection(server + "postgres", pg.username(), pg.password());
             Statement st = c.createStatement()) {
            st.execute("CREATE DATABASE " + database);
        } catch (SQLException e) {
            throw BusinessException.validation("Could not create the cloud database: " + e.getMessage());
        }
        return new Tenant(code, name, mode, server + database, pg.username(), pg.password(), TenantStatus.ACTIVE, null, null);
    }

    /** Brings a shop's schema up to date and returns its version. */
    public String migrate(String code) {
        MigrateResult result = Flyway.configure()
                .dataSource(dataSources.forTenant(code))
                .locations("classpath:db/tenant")
                .load()
                .migrate();
        return result.targetSchemaVersion != null ? result.targetSchemaVersion : result.initialSchemaVersion;
    }
}
