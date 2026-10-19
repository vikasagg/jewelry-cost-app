package com.swarnos.common.audit.domain;

import java.time.Instant;

public record AuditEntry(long id, Instant at, String username, String action, String entity, String entityId, String detail) {}
