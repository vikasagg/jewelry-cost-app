package com.aijewel.erp.auth;

import com.aijewel.erp.common.ApiException;

public final class CurrentUser {
    private static final ThreadLocal<AuthUser> CURRENT = new ThreadLocal<>();

    private CurrentUser() {}

    static void set(AuthUser user) {
        CURRENT.set(user);
    }

    static void clear() {
        CURRENT.remove();
    }

    public static AuthUser get() {
        return CURRENT.get();
    }

    public static String usernameOrSystem() {
        AuthUser u = CURRENT.get();
        return u == null ? "system" : u.username();
    }

    public static boolean can(Permission p) {
        AuthUser u = CURRENT.get();
        return u == null || p.allows(u.role());   // null = system jobs (demo seeding, tests)
    }

    public static void require(Permission p) {
        if (!can(p)) throw ApiException.forbidden("Your role is not allowed to do this (" + p + ").");
    }
}
