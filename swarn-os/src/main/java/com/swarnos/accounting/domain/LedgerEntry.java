package com.swarnos.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

public record LedgerEntry(long id, Book book, LocalDate businessDate, Long partyId, DocumentType docType, long docId,
                          BigDecimal debit, BigDecimal credit, String narration, Instant createdAt) {}
