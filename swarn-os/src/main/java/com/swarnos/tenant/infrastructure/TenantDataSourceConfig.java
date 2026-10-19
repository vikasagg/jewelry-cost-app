package com.swarnos.tenant.infrastructure;

import javax.sql.DataSource;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.PlatformTransactionManager;

/** The default data source, JDBC client and transactions all follow the current shop. */
@Configuration
public class TenantDataSourceConfig {

    @Bean
    @Primary
    DataSource tenantDataSource(TenantDataSources dataSources) {
        return new TenantRoutingDataSource(dataSources);
    }

    @Bean
    @Primary
    JdbcClient tenantJdbc(DataSource tenantDataSource) {
        return JdbcClient.create(tenantDataSource);
    }

    @Bean
    @Primary
    PlatformTransactionManager transactionManager(DataSource tenantDataSource) {
        return new DataSourceTransactionManager(tenantDataSource);
    }
}
