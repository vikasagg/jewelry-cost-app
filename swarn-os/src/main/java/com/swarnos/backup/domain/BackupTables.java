package com.swarnos.backup.domain;

import java.util.List;

/** Every table of a shop database, parents before children so a restore never breaks a foreign key. */
public final class BackupTables {
    public static final List<String> ALL = List.of(
            "app_config", "app_user", "audit_log", "doc_sequence", "location", "category", "purity", "party",
            "rate_set", "rate_line", "item", "stone", "stock_movement", "purchase", "purchase_line", "sale", "sale_line",
            "sale_exchange", "payment", "ledger_entry", "repair_job", "repair_event", "tally_session", "tally_expected",
            "tally_scan", "tally_variance", "backup_log");

    private BackupTables() {}
}
