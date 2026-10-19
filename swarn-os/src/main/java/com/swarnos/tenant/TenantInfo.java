package com.swarnos.tenant;

public record TenantInfo(String code, String name, String storageMode, String jdbcUrl,
                         String dbUsername, String dbPassword, String status, String schemaVersion) {}
