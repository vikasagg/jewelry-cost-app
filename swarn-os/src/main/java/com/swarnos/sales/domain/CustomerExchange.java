package com.swarnos.sales.domain;

import java.math.BigDecimal;
import java.time.LocalDate;

/** Old metal a customer gave in exchange, for their history. */
public record CustomerExchange(String invoiceNo, LocalDate businessDate, String description, String metal, String purityCode,
                               BigDecimal netWt, BigDecimal exchangeValue) {}
