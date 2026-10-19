package com.swarnos.security;

import com.swarnos.common.error.BusinessException;
import java.util.function.Supplier;

/** Holds the signed-in user for the current request thread; checks permissions. */
public final class CurrentUser {
    private static final ThreadLocal<AuthUser> CURRENT = new ThreadLocal<>();

    private CurrentUser() {}

    public static void set(AuthUser user) {
        CURRENT.set(user);
    }

    public static void clear() {
        CURRENT.remove();
    }

    public static AuthUser get() {
        return CURRENT.get();
    }

    public static String usernameOrSystem() {
        AuthUser u = CURRENT.get();
        return u == null ? "system" : u.username();
    }

    /** No user means a system job (start-up seeding), which may do everything. */
    public static boolean can(Permission p) {
        AuthUser u = CURRENT.get();
        return u == null || p.allows(u.role());
    }

    public static void require(Permission p) {
        if (!can(p)) throw BusinessException.forbidden("Your role is not allowed to do this (" + p + ").");
    }

    /** Runs work as a given user, restoring the previous one afterwards. */
    public static <T> T runAs(AuthUser user, Supplier<T> work) {
        AuthUser previous = CURRENT.get();
        CURRENT.set(user);
        try {
            return work.get();
        } finally {
            if (previous == null) CURRENT.remove(); else CURRENT.set(previous);
        }
    }
}
