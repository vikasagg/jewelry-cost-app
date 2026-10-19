package com.swarnos.tally.domain;

import java.time.Instant;

public record RecentScan(String code, Instant scannedAt, String name) {}
