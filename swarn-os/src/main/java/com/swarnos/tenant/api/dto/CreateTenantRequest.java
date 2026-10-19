package com.swarnos.tenant.api.dto;

import com.swarnos.tenant.domain.StorageMode;

public record CreateTenantRequest(String code, String name, StorageMode storageMode, String ownerUsername,
                                  String ownerName, String ownerPassword) {}
