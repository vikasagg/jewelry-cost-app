package com.swarnos.identity.domain;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.swarnos.security.Role;
import java.time.Instant;

public record User(long id, String username, String fullName, @JsonIgnore String passwordHash, Role role, boolean active,
                   Instant createdAt) {
    public static final int MIN_PASSWORD_LENGTH = 6;
}
