package com.swarnos.reports;

import com.swarnos.common.BusinessClock;
import com.swarnos.common.Rows;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.Map;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class ReportController {
    private final ReportService reports;
    private final BusinessClock clock;

    public ReportController(ReportService reports, BusinessClock clock) {
        this.reports = reports;
        this.clock = clock;
    }

    @GetMapping("/dashboard")
    public Map<String, Object> dashboard() {
        return reports.dashboard();
    }

    @GetMapping("/reports")
    public Map<String, String> catalogue() {
        return ReportService.CATALOGUE;
    }

    @GetMapping("/reports/{name}")
    public ReportService.Report run(@PathVariable String name, @RequestParam(required = false) String from,
                                    @RequestParam(required = false) String to) {
        return reports.run(name, fromDate(from, to), toDate(to));
    }

    /** CSV opens directly in Excel (BRD FR-RPT-02). */
    @GetMapping("/reports/{name}/csv")
    public ResponseEntity<byte[]> csv(@PathVariable String name, @RequestParam(required = false) String from,
                                      @RequestParam(required = false) String to) {
        ReportService.Report r = reports.run(name, fromDate(from, to), toDate(to));
        StringBuilder sb = new StringBuilder("﻿");
        sb.append(String.join(",", r.columns().stream().map(c -> quote(c.label())).toList())).append("\r\n");
        for (Map<String, Object> row : r.rows()) {
            sb.append(String.join(",", r.columns().stream().map(c -> quote(row.get(c.key()))).toList())).append("\r\n");
        }
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + name + "_" + toDate(to) + ".csv\"")
                .contentType(new MediaType("text", "csv", StandardCharsets.UTF_8))
                .body(sb.toString().getBytes(StandardCharsets.UTF_8));
    }

    private LocalDate toDate(String to) {
        return to == null || to.isBlank() ? clock.today() : Rows.date(to);
    }

    private LocalDate fromDate(String from, String to) {
        return from == null || from.isBlank() ? toDate(to).withDayOfMonth(1) : Rows.date(from);
    }

    private static String quote(Object o) {
        String s = o == null ? "" : o.toString();
        return s.matches(".*[\",\\r\\n].*") ? "\"" + s.replace("\"", "\"\"") + "\"" : s;
    }
}
