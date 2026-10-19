package com.swarnos.backup.api.dto;

public record BackupRequest(String password, String targetDir) {}
