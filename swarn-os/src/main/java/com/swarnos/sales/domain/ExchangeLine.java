package com.swarnos.sales.domain;

import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;

/** Customer's old gold or silver taken against a bill. */
public record ExchangeLine(long id, long saleId, String description, Metal metal, String purityCode, BigDecimal grossWt,
                           BigDecimal netWt, BigDecimal fineWt, BigDecimal rate, BigDecimal deductionPct, BigDecimal exchangeValue) {}
