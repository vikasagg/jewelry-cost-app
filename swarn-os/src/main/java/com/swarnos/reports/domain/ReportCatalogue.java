package com.swarnos.reports.domain;

import java.util.LinkedHashMap;
import java.util.Map;

/** Every report the shop can run (BRD §12). */
public final class ReportCatalogue {
    public static final Map<String, String> REPORTS = new LinkedHashMap<>();

    static {
        REPORTS.put("stock_summary", "Stock summary by category");
        REPORTS.put("stock_metal", "Stock by metal and purity");
        REPORTS.put("stock_ageing", "Stock ageing");
        REPORTS.put("tag_stock", "Tag-wise stock");
        REPORTS.put("sales_register", "Sales register");
        REPORTS.put("sales_items", "Item-wise sales");
        REPORTS.put("sales_by_category", "Sales by category");
        REPORTS.put("sales_by_salesperson", "Sales by salesperson");
        REPORTS.put("purchase_register", "Purchase register");
        REPORTS.put("purchase_by_mode", "Purchases by mode (cash / bank / gold / silver)");
        REPORTS.put("purchase_by_class", "Purchases by class (Seen / Unseen)");
        REPORTS.put("old_metal", "Old metal bought and exchanged");
        REPORTS.put("outstanding", "Customer and vendor outstanding");
        REPORTS.put("repairs_open", "Open and overdue repairs");
        REPORTS.put("repairs_karigar", "Karigar-wise metal difference");
        REPORTS.put("tally_history", "Daily tally and variance");
        REPORTS.put("rate_history", "Metal rate history");
        REPORTS.put("gst_summary", "GST summary (sales)");
        REPORTS.put("huid_register", "HUID / hallmark register");
        REPORTS.put("backup_log", "Backup log");
    }

    private ReportCatalogue() {}
}
