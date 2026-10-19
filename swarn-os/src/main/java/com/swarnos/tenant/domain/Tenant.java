package com.swarnos.tenant.domain;

import java.time.Instant;
import java.util.regex.Pattern;

/** A shop using Swarn-OS, and where its own database lives. */
public record Tenant(String code, String name, StorageMode storageMode, String jdbcUrl, String dbUsername,
                     String dbPassword, TenantStatus status, String schemaVersion, Instant createdAt) {

    private static final Pattern CODE = Pattern.compile("[a-z][a-z0-9]{1,19}");
    /** Local databases are stored relative to the data folder so it can be moved or copied. */
    public static final String LOCAL_URL_PREFIX = "h2:";

    public static boolean isValidCode(String code) {
        return code != null && CODE.matcher(code).matches();
    }

    public boolean isActive() {
        return status == TenantStatus.ACTIVE;
    }

    /** Where the database is, for display: data/tenants/... or the JDBC URL. */
    public String databaseLocation() {
        return jdbcUrl.startsWith(LOCAL_URL_PREFIX) ? "data/" + jdbcUrl.substring(LOCAL_URL_PREFIX.length()) : jdbcUrl;
    }
}
