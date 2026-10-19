package com.aijewel.erp.tenant;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/** Brings every shop's database up to the current schema at start-up. */
@Component
@Order(1)
public class StartupMigrations implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(StartupMigrations.class);
    private final TenantProvisioner provisioner;

    public StartupMigrations(TenantProvisioner provisioner) {
        this.provisioner = provisioner;
    }

    @Override
    public void run(ApplicationArguments args) {
        var failed = provisioner.migrateAll();
        if (!failed.isEmpty()) log.warn("Shops that failed to upgrade: {}", failed);
    }
}
