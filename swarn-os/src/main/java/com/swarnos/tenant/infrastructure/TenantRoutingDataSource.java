package com.swarnos.tenant.infrastructure;

import java.sql.Connection;
import java.sql.SQLException;
import org.springframework.jdbc.datasource.AbstractDataSource;

/** Hands out connections to the database of the shop in {@link TenantContext}. */
public class TenantRoutingDataSource extends AbstractDataSource {
    private final TenantDataSources dataSources;

    public TenantRoutingDataSource(TenantDataSources dataSources) {
        this.dataSources = dataSources;
    }

    @Override
    public Connection getConnection() throws SQLException {
        return dataSources.forTenant(TenantContext.require()).getConnection();
    }

    @Override
    public Connection getConnection(String username, String password) throws SQLException {
        return getConnection();
    }
}
