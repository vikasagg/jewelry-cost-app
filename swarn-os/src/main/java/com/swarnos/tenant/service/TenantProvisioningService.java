package com.swarnos.tenant.service;

import com.swarnos.common.error.BusinessException;
import com.swarnos.identity.domain.User;
import com.swarnos.identity.service.UserService;
import com.swarnos.settings.domain.SettingKeys;
import com.swarnos.settings.service.SettingsService;
import com.swarnos.tenant.domain.StorageMode;
import com.swarnos.tenant.domain.Tenant;
import com.swarnos.tenant.infrastructure.TenantContext;
import com.swarnos.tenant.infrastructure.TenantDataSources;
import com.swarnos.tenant.infrastructure.TenantDatabaseFactory;
import com.swarnos.tenant.repository.TenantRepository;
import java.util.ArrayList;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Onboards a shop with its own database (BRD FR-TEN-01, FR-TEN-03) and keeps
 * every shop's schema migrated (FR-TEN-04).
 */
@Service
public class TenantProvisioningService {
    private static final Logger log = LoggerFactory.getLogger(TenantProvisioningService.class);

    private final TenantRepository repository;
    private final TenantService tenants;
    private final TenantDatabaseFactory databases;
    private final TenantDataSources dataSources;
    private final UserService users;
    private final SettingsService settings;

    public TenantProvisioningService(TenantRepository repository, TenantService tenants, TenantDatabaseFactory databases,
                                     TenantDataSources dataSources, UserService users, SettingsService settings) {
        this.repository = repository;
        this.tenants = tenants;
        this.databases = databases;
        this.dataSources = dataSources;
        this.users = users;
        this.settings = settings;
    }

    public record NewShop(String code, String name, StorageMode storageMode, String ownerUsername, String ownerName,
                          String ownerPassword) {}

    public Tenant create(NewShop req) {
        String code = req.code() == null ? "" : req.code().trim().toLowerCase();
        if (!Tenant.isValidCode(code)) throw BusinessException.validation("Shop code must be 2-20 letters/digits starting with a letter.");
        if (tenants.find(code).isPresent()) throw BusinessException.conflict("Shop code already in use: " + code);
        if (req.name() == null || req.name().isBlank()) throw BusinessException.validation("Shop name is required.");
        if (req.ownerPassword() == null || req.ownerPassword().length() < User.MIN_PASSWORD_LENGTH) {
            throw BusinessException.validation("Owner password must have at least " + User.MIN_PASSWORD_LENGTH + " characters.");
        }
        StorageMode mode = req.storageMode() == null ? StorageMode.LOCAL : req.storageMode();

        Tenant tenant = databases.newDatabase(code, req.name().trim(), mode);
        repository.insert(tenant);
        try {
            migrate(code);
            TenantContext.run(code, () -> {
                users.createOwner(req.ownerUsername(), req.ownerName(), req.ownerPassword());
                settings.write(SettingKeys.SHOP_NAME, tenant.name());
            });
        } catch (RuntimeException e) {
            dataSources.close(code);
            repository.delete(code);
            throw e;
        }
        log.info("Created shop {} ({}, {})", code, tenant.name(), mode);
        return tenants.require(code);
    }

    public String migrate(String code) {
        String version = databases.migrate(code);
        repository.updateSchemaVersion(code, version);
        return version;
    }

    /** Upgrades every shop; one failing shop does not stop the others. Returns the failures. */
    public List<String> migrateAll() {
        List<String> failed = new ArrayList<>();
        for (Tenant t : tenants.list()) {
            try {
                migrate(t.code());
            } catch (RuntimeException e) {
                log.error("Migration failed for shop {}", t.code(), e);
                failed.add(t.code() + ": " + e.getMessage());
            }
        }
        return failed;
    }
}
