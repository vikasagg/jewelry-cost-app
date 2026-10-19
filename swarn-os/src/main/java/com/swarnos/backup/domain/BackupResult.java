package com.swarnos.backup.domain;

public record BackupResult(String file, String path, long sizeBytes, String sha256, long rows, boolean verified) {}
