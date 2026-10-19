package com.swarnos.tenant.api.dto;

import com.swarnos.tenant.domain.StorageMode;
import com.swarnos.tenant.domain.Tenant;
import com.swarnos.tenant.domain.TenantStatus;

/** Shop as shown to the platform operator; never exposes database credentials. */
public record TenantResponse(String code, String name, StorageMode storageMode, String database, TenantStatus status,
                             String schemaVersion) {

    public static TenantResponse from(Tenant t) {
        return new TenantResponse(t.code(), t.name(), t.storageMode(), t.databaseLocation(), t.status(),
                t.schemaVersion() == null ? "" : t.schemaVersion());
    }
}
