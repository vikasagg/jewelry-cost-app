package com.aijewel.erp.rates;

import java.math.BigDecimal;

/** Base rates per gram: 24K gold, fine silver, platinum. */
public record LiveRates(BigDecimal gold24k, BigDecimal silver, BigDecimal platinum, String provider) {}
