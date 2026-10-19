package com.swarnos.backup.domain;

import java.util.Map;

public record BackupInspection(String shop, String createdAt, String createdBy, String sha256, long rows, Map<String, Integer> tables) {}
