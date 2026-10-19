package com.swarnos.tenant.infrastructure;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

final class ConnectionPools {
    private ConnectionPools() {}

    static HikariDataSource create(String name, String url, String user, String password, int size) {
        HikariConfig cfg = new HikariConfig();
        cfg.setPoolName(name);
        cfg.setJdbcUrl(url);
        cfg.setUsername(user);
        cfg.setPassword(password == null ? "" : password);
        cfg.setMaximumPoolSize(size);
        cfg.setMinimumIdle(0);
        return new HikariDataSource(cfg);
    }
}
