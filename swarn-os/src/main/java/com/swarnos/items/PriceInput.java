package com.swarnos.items;

import java.math.BigDecimal;

/** Everything needed to price one item at a given rate. */
public record PriceInput(
        String pricingMode,     // METAL | FIXED
        BigDecimal netWt,
        BigDecimal ratePerGram,
        String makingType,      // PER_GRAM | PERCENT | FIXED
        BigDecimal makingValue,
        BigDecimal wastagePct,
        BigDecimal stoneValue,
        BigDecimal fixedPrice,
        int quantity,
        BigDecimal gstPct) {}
