package com.swarnos.sales.domain;

import java.math.BigDecimal;
import java.time.LocalDate;

/** An item a customer bought, for their permanent history (FR-CUS-02). */
public record CustomerPurchase(String invoiceNo, LocalDate businessDate, SaleStatus status, String description,
                               String purityCode, BigDecimal netWt, BigDecimal rate, BigDecimal lineTotal, String tagCode) {}
