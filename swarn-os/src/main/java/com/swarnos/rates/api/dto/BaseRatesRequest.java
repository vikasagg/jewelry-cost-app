package com.swarnos.rates.api.dto;

import com.swarnos.rates.domain.BaseRates;
import java.math.BigDecimal;

/** Per-gram base rates typed in each morning; {@code approve_now} saves and approves in one step. */
public record BaseRatesRequest(BigDecimal gold24k, BigDecimal silver, BigDecimal platinum, Boolean approveNow, String note) {

    public BaseRates toBaseRates() {
        return new BaseRates(gold24k, silver, platinum);
    }
}
