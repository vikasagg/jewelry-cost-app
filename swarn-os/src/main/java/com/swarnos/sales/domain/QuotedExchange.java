package com.swarnos.sales.domain;

import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;

public record QuotedExchange(String description, Metal metal, String purityCode, BigDecimal grossWt, BigDecimal netWt,
                             BigDecimal fineWt, BigDecimal rate, BigDecimal deductionPct, BigDecimal value) {}
