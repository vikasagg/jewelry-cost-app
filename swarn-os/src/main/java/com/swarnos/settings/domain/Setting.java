package com.swarnos.settings.domain;

import java.time.Instant;

public record Setting(String configKey, String configValue, String description, String updatedBy, Instant updatedAt) {}
