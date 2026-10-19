package com.swarnos.security;

/** The signed-in person and the shop they belong to ("_platform" for the operator). */
public record AuthUser(String tenant, String username, String fullName, Role role) {
    public static final String PLATFORM_TENANT = "_platform";
}
