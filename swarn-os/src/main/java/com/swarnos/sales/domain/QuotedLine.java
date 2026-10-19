package com.swarnos.sales.domain;

import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;

/** One item priced for a bill. */
public record QuotedLine(long itemId, String tagCode, String description, Metal metal, String purityCode, int quantity,
                         BigDecimal grossWt, BigDecimal netWt, String huid, BigDecimal rate, BigDecimal metalValue,
                         BigDecimal wastageValue, BigDecimal makingValue, BigDecimal stoneValue, BigDecimal discount,
                         BigDecimal taxable, BigDecimal gstPct, BigDecimal gst, BigDecimal lineTotal) {}
