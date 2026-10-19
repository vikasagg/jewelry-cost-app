package com.swarnos.tenant;

import javax.sql.DataSource;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration
public class DataSourceConfig {

    @Bean
    @Primary
    DataSource tenantDataSource(TenantRegistry registry) {
        return new TenantRoutingDataSource(registry);
    }

    @Bean
    JdbcClient jdbcClient(DataSource tenantDataSource) {
        return JdbcClient.create(tenantDataSource);
    }

    @Bean
    PlatformTransactionManager transactionManager(DataSource tenantDataSource) {
        return new DataSourceTransactionManager(tenantDataSource);
    }
}
