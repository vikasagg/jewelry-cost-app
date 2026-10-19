package com.swarnos.rates.domain;

import com.swarnos.common.money.Decimals;
import com.swarnos.settings.domain.Purity;
import java.util.List;

/**
 * Derives every purity's rate from the base rates (owner decisions D-01, D-02):
 * rate = base x price factor, e.g. 22K = 24K x 0.92, rounded to 3 decimals.
 */
public final class RateDerivation {
    private RateDerivation() {}

    public static List<RateLine> derive(BaseRates base, List<Purity> purities) {
        return purities.stream()
                .map(p -> new RateLine(p.metal(), p.code(), Decimals.multiply(base.of(p.metal()), p.priceFactor()), p.priceFactor()))
                .toList();
    }
}
