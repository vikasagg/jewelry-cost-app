package com.swarnos.rates.domain;

import com.swarnos.common.money.Decimals;
import java.math.BigDecimal;

/**
 * Value of old gold or silver taken in exchange or bought ("treat" purchase):
 * net weight x today's rate for the tested purity, less the deduction %;
 * fine weight = net weight x fineness, for the metal books.
 */
public record MetalValuation(BigDecimal value, BigDecimal fineWeight) {

    public static MetalValuation of(BigDecimal netWeight, BigDecimal ratePerGram, BigDecimal deductionPct, BigDecimal fineness) {
        BigDecimal gross = Decimals.multiply(netWeight, ratePerGram);
        BigDecimal value = Decimals.round(gross.subtract(Decimals.percentOf(gross, deductionPct)));
        return new MetalValuation(value, Decimals.multiply(netWeight, fineness));
    }
}
