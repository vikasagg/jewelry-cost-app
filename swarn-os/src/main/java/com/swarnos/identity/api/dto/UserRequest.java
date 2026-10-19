package com.swarnos.identity.api.dto;

import com.swarnos.security.Role;

public record UserRequest(String username, String fullName, Role role, String password, Boolean active) {}
