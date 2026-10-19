package com.swarnos.common.numbering.repository;

import com.swarnos.common.persistence.SqlSupport;
import org.springframework.stereotype.Repository;

@Repository
public class DocumentSequenceRepository {
    private final SqlSupport sql;

    public DocumentSequenceRepository(SqlSupport sql) {
        this.sql = sql;
    }

    /** Takes the next number of a series; the row lock makes it safe inside a transaction. */
    public long next(String series) {
        int updated = sql.update("UPDATE doc_sequence SET next_value = next_value + 1 WHERE series = ?", series);
        if (updated == 0) {
            sql.update("INSERT INTO doc_sequence (series, next_value) VALUES (?, 2)", series);
            return 1;
        }
        return sql.scalar("SELECT next_value - 1 FROM doc_sequence WHERE series = ?", Long.class, series);
    }
}
