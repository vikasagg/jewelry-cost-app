package com.aijewel.erp.auth;

public record AuthUser(String tenant, String username, String fullName, Role role) {}
