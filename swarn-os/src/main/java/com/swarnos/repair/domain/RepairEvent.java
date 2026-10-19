package com.swarnos.repair.domain;

import java.math.BigDecimal;
import java.time.Instant;

public record RepairEvent(long id, long jobId, RepairStatus status, BigDecimal weight, String note, String username, Instant at) {}
