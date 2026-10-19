package com.swarnos.rates.domain;

import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;

/** Per-gram base rates: 24K gold, fine silver and platinum. Every other purity is derived from these. */
public record BaseRates(BigDecimal gold24k, BigDecimal silver, BigDecimal platinum) {

    public BaseRates {
        gold24k = Decimals.roundOrNull(gold24k);
        silver = Decimals.roundOrNull(silver);
        platinum = Decimals.roundOrNull(platinum);
    }

    public BaseRates requireAllPositive() {
        if (!Decimals.isPositive(gold24k) || !Decimals.isPositive(silver) || !Decimals.isPositive(platinum)) {
            throw BusinessException.validation("Gold, silver and platinum rates must all be more than zero.");
        }
        return this;
    }

    public BigDecimal of(Metal metal) {
        return switch (metal) {
            case GOLD -> gold24k;
            case SILVER -> silver;
            case PLATINUM -> platinum;
        };
    }
}
