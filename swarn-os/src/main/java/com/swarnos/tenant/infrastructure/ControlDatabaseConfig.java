package com.swarnos.tenant.infrastructure;

import com.swarnos.common.config.AppProperties;
import com.zaxxer.hikari.HikariDataSource;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.simple.JdbcClient;

/** The control-plane database: shop registry and routing only, never business data. */
@Configuration
public class ControlDatabaseConfig {
    public static final String CONTROL = "controlJdbc";

    @Bean(destroyMethod = "close")
    @Qualifier("controlDataSource")
    HikariDataSource controlDataSource(AppProperties props, DataPaths paths) {
        AppProperties.ControlDb cfg = props.controlDb();
        boolean external = cfg != null && cfg.url() != null && !cfg.url().isBlank();
        HikariDataSource ds = ConnectionPools.create("control",
                external ? cfg.url() : DataPaths.h2Url(paths.root().resolve("control")),
                external ? cfg.username() : "sa", external ? cfg.password() : "", 4);
        Flyway.configure().dataSource(ds).locations("classpath:db/control").load().migrate();
        return ds;
    }

    @Bean(CONTROL)
    JdbcClient controlJdbc(@Qualifier("controlDataSource") DataSource controlDataSource) {
        return JdbcClient.create(controlDataSource);
    }
}
