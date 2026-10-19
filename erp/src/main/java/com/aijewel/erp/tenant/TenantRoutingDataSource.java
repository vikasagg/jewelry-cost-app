package com.aijewel.erp.tenant;

import java.sql.Connection;
import java.sql.SQLException;
import org.springframework.jdbc.datasource.AbstractDataSource;

/** Hands out connections to the database of the shop in {@link TenantContext}. */
public class TenantRoutingDataSource extends AbstractDataSource {
    private final TenantRegistry registry;

    public TenantRoutingDataSource(TenantRegistry registry) {
        this.registry = registry;
    }

    @Override
    public Connection getConnection() throws SQLException {
        return registry.dataSource(TenantContext.require()).getConnection();
    }

    @Override
    public Connection getConnection(String username, String password) throws SQLException {
        return getConnection();
    }
}
