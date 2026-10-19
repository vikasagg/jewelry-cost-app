package com.swarnos.settings.domain;

public record Location(long id, String code, String name, LocationKind kind) {
    public static final String DEFAULT_COUNTER = "C1";
}
