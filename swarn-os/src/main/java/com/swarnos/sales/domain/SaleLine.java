package com.swarnos.sales.domain;

import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;

/** A billed item; tag code, gross and stone weight come from the item when reading. */
public record SaleLine(long id, long saleId, long itemId, String description, Metal metal, String purityCode, int quantity,
                       BigDecimal netWt, BigDecimal rate, BigDecimal metalValue, BigDecimal wastageValue, BigDecimal makingValue,
                       BigDecimal stoneValue, BigDecimal discount, BigDecimal taxable, BigDecimal gstPct, BigDecimal gst,
                       BigDecimal lineTotal, String huid, String tagCode, BigDecimal grossWt, BigDecimal stoneWt) {}
