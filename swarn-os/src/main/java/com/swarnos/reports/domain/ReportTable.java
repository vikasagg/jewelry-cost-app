package com.swarnos.reports.domain;

import com.swarnos.common.money.Decimals;
import java.math.BigDecimal;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** A report as a table: the screen, the CSV export and the print view share this one shape. */
public record ReportTable(String title, List<Column> columns, List<Map<String, Object>> rows, Map<String, Object> totals) {

    /** Table with totals of every numeric column. */
    public static ReportTable of(String title, List<Map<String, Object>> rows, String... columnSpecs) {
        List<Column> columns = Arrays.stream(columnSpecs).map(Column::of).toList();
        return new ReportTable(title, columns, rows, totals(rows, columns.stream().filter(Column::isNumeric).map(Column::key).toList()));
    }

    public static Map<String, Object> totals(List<Map<String, Object>> rows, List<String> keys) {
        Map<String, Object> totals = new LinkedHashMap<>();
        for (String k : keys) {
            BigDecimal t = Decimals.ZERO;
            for (Map<String, Object> r : rows) if (r.get(k) instanceof Number n) t = t.add(new BigDecimal(n.toString()));
            totals.put(k, Decimals.round(t));
        }
        return totals;
    }
}
