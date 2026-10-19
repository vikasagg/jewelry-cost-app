package com.swarnos.auth;

public record AuthUser(String tenant, String username, String fullName, Role role) {}
