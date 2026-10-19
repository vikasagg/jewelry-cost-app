package com.swarnos.tenant.infrastructure;

import com.swarnos.common.error.BusinessException;
import java.util.function.Supplier;

/** The shop whose database the current thread uses. */
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
        if (code == null) throw BusinessException.forbidden("No shop selected for this request.");
        return code;
    }

    public static void clear() {
        CURRENT.remove();
    }

    /** Runs work against a given shop's database, restoring the previous shop afterwards. */
    public static <T> T call(String code, Supplier<T> work) {
        String previous = CURRENT.get();
        CURRENT.set(code);
        try {
            return work.get();
        } finally {
            if (previous == null) CURRENT.remove(); else CURRENT.set(previous);
        }
    }

    public static void run(String code, Runnable work) {
        call(code, () -> {
            work.run();
            return null;
        });
    }
}
