package com.swarnos.accounting.domain;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/** One book between two dates with opening, running and closing balance. */
public record BookStatement(Book book, LocalDate from, LocalDate to, BigDecimal opening, BigDecimal totalDebit,
                            BigDecimal totalCredit, BigDecimal closing, List<Line> entries) {

    public record Line(LocalDate businessDate, DocumentType docType, long docId, String narration, String partyName,
                       BigDecimal debit, BigDecimal credit, BigDecimal balance) {}
}
