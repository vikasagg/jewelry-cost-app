package com.swarnos.sales.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

public record Sale(long id, String invoiceNo, LocalDate businessDate, Long customerId, long rateSetId, BigDecimal itemsTotal,
                   BigDecimal discount, BigDecimal taxableTotal, BigDecimal gstTotal, BigDecimal exchangeTotal,
                   BigDecimal roundOff, BigDecimal netPayable, BigDecimal paidTotal, BigDecimal balanceDue, SaleStatus status,
                   String notes, String createdBy, Instant createdAt) {}
