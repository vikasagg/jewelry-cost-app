package com.aijewel.erp.tenant;

import com.aijewel.erp.common.ApiException;

/** The shop (tenant) the current request belongs to. */
public final class TenantContext {
    private static final ThreadLocal<String> CURRENT = new ThreadLocal<>();

    private TenantContext() {}

    public static void set(String code) {
        CURRENT.set(code);
    }

    public static String get() {
        return CURRENT.get();
    }

    public static String require() {
        String code = CURRENT.get();
        if (code == null) throw ApiException.forbidden("No shop selected for this request.");
        return code;
    }

    public static void clear() {
        CURRENT.remove();
    }

    /** Runs work against a given tenant's database, restoring the previous tenant afterwards. */
    public static <T> T call(String code, java.util.function.Supplier<T> work) {
        String previous = CURRENT.get();
        CURRENT.set(code);
        try {
            return work.get();
        } finally {
            if (previous == null) CURRENT.remove(); else CURRENT.set(previous);
        }
    }
}
