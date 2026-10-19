package com.swarnos.common;

import java.time.LocalDate;
import org.springframework.stereotype.Service;

/** Gap-free document numbers per series and financial year, e.g. INV/2026-27/000001. */
@Service
public class DocNumbers {
    private final Db db;

    public DocNumbers(Db db) {
        this.db = db;
    }

    public String next(String prefix, LocalDate date) {
        String series = prefix + "/" + financialYear(date);
        long n = nextValue(series);
        return series + "/" + String.format("%06d", n);
    }

    /** Plain counter without year, used for tag codes. */
    public long nextValue(String series) {
        int updated = db.update("UPDATE doc_sequence SET next_value = next_value + 1 WHERE series = ?", series);
        if (updated == 0) {
            db.update("INSERT INTO doc_sequence (series, next_value) VALUES (?, 2)", series);
            return 1;
        }
        return db.value("SELECT next_value - 1 FROM doc_sequence WHERE series = ?", Long.class, series);
    }

    static String financialYear(LocalDate d) {
        int start = d.getMonthValue() >= 4 ? d.getYear() : d.getYear() - 1;
        return start + "-" + String.format("%02d", (start + 1) % 100);
    }
}
