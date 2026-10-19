package com.swarnos.purchase.domain;

import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;

/** Old gold or silver bought by weight; deduction and rate default from settings and today's rate. */
public record OldMetalLine(String description, Metal metal, String purityCode, BigDecimal grossWt, BigDecimal netWt,
                           BigDecimal deductionPct, BigDecimal rate) {}
