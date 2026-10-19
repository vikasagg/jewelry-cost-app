package com.swarnos.tenant.domain;

/** LOCAL = H2 file on the shop server (works with no internet); CLOUD = its own PostgreSQL database. */
public enum StorageMode {
    LOCAL, CLOUD
}
