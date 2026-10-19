package com.swarnos.items;

import java.math.BigDecimal;

public record PriceBreakdown(
        BigDecimal rate,
        BigDecimal metalValue,
        BigDecimal wastageValue,
        BigDecimal makingValue,
        BigDecimal stoneValue,
        BigDecimal discount,
        BigDecimal taxable,
        BigDecimal gstPct,
        BigDecimal gst,
        BigDecimal total) {}
