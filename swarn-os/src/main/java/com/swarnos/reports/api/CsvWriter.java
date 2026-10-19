package com.swarnos.reports.api;

import com.swarnos.reports.domain.Column;
import com.swarnos.reports.domain.ReportTable;
import java.util.Map;

/** Writes a report table as CSV with a BOM so Excel reads UTF-8 (rupee sign, Hindi names). */
final class CsvWriter {
    private CsvWriter() {}

    static String write(ReportTable table) {
        StringBuilder sb = new StringBuilder("﻿");
        sb.append(String.join(",", table.columns().stream().map(c -> quote(c.label())).toList())).append("\r\n");
        for (Map<String, Object> row : table.rows()) {
            sb.append(String.join(",", table.columns().stream().map(Column::key).map(k -> quote(row.get(k))).toList())).append("\r\n");
        }
        return sb.toString();
    }

    private static String quote(Object o) {
        String s = o == null ? "" : o.toString();
        return s.matches("(?s).*[\",\\r\\n].*") ? "\"" + s.replace("\"", "\"\"") + "\"" : s;
    }
}
