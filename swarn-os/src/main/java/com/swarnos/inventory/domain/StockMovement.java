package com.swarnos.inventory.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

/** One change of stock. Item status is a cache of the latest movement (BRD FR-STK-01..03). */
public record StockMovement(long id, long itemId, MovementType movementType, int qty, BigDecimal grossWt, BigDecimal netWt,
                            ItemStatus statusAfter, String docType, Long docId, LocalDate businessDate, String username,
                            Instant createdAt, String idemKey, String note) {}
