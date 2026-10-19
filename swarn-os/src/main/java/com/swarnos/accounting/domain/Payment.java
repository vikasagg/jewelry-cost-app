package com.swarnos.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

public record Payment(long id, DocumentType docType, long docId, Long partyId, Direction direction, PaymentMode mode,
                      BigDecimal amount, String reference, LocalDate businessDate, String createdBy, Instant createdAt) {}
