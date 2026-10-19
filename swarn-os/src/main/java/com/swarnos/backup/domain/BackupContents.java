package com.swarnos.backup.domain;

import java.util.List;
import java.util.Map;

/** What a backup file holds: the shop and every table's rows. */
public record BackupContents(String format, String shop, String createdAt, String createdBy,
                             Map<String, List<Map<String, Object>>> tables) {
    public static final String FORMAT = "Swarn-OS backup v1";

    public long rowCount() {
        return tables.values().stream().mapToLong(List::size).sum();
    }
}
