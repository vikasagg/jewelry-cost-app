package com.swarnos.reports.api;

import com.swarnos.common.api.DateRange;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.reports.domain.ReportTable;
import com.swarnos.reports.service.ReportService;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.Map;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/reports")
public class ReportController {
    private final ReportService reports;
    private final BusinessClock clock;

    public ReportController(ReportService reports, BusinessClock clock) {
        this.reports = reports;
        this.clock = clock;
    }

    @GetMapping
    public Map<String, String> catalogue() {
        return reports.catalogue();
    }

    @GetMapping("/{name}")
    public ReportTable run(@PathVariable String name,
                           @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                           @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        DateRange range = DateRange.monthToDate(from, to, clock.today());
        return reports.run(name, range.from(), range.to());
    }

    /** CSV that opens directly in Excel (FR-RPT-02). */
    @GetMapping("/{name}/csv")
    public ResponseEntity<byte[]> csv(@PathVariable String name,
                                      @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                                      @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        DateRange range = DateRange.monthToDate(from, to, clock.today());
        ReportTable table = reports.run(name, range.from(), range.to());
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + name + "_" + range.to() + ".csv\"")
                .contentType(new MediaType("text", "csv", StandardCharsets.UTF_8))
                .body(CsvWriter.write(table).getBytes(StandardCharsets.UTF_8));
    }
}
