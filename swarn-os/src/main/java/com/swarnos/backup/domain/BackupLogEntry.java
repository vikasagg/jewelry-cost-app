package com.swarnos.backup.domain;

import java.time.Instant;

public record BackupLogEntry(long id, Instant at, String username, String fileName, String target, long sizeBytes, String sha256,
                             long rowCount, boolean verified) {}
