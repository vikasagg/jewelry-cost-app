package com.swarnos.backup.api.dto;

import com.swarnos.backup.domain.BackupLogEntry;
import java.util.List;

public record BackupOverview(String targetDir, List<BackupLogEntry> log) {}
