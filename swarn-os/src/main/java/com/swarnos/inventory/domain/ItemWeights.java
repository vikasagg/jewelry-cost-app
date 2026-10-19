package com.swarnos.inventory.domain;

import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import java.math.BigDecimal;
import java.util.List;

/**
 * Gross, stone and net weight of a metal item. Stone weight defaults to total
 * carats x 0.2 g; net weight defaults to gross - stone.
 */
public record ItemWeights(BigDecimal gross, BigDecimal stone, BigDecimal net) {
    static final BigDecimal GRAMS_PER_CARAT = new BigDecimal("0.2");

    public static ItemWeights resolve(BigDecimal gross, BigDecimal stoneWt, BigDecimal netWt, List<NewStone> stones) {
        BigDecimal g = Decimals.orZero(gross);
        BigDecimal s = stoneWt != null ? Decimals.round(stoneWt)
                : Decimals.multiply(stones.stream().map(st -> Decimals.orZero(st.carat())).reduce(BigDecimal.ZERO, BigDecimal::add),
                        GRAMS_PER_CARAT);
        BigDecimal n = netWt != null ? Decimals.round(netWt) : Decimals.round(g.subtract(s));
        if (!Decimals.isPositive(g) || !Decimals.isPositive(n)) throw BusinessException.validation("Gross and net weight must be more than zero.");
        if (n.compareTo(g) > 0) throw BusinessException.validation("Net weight cannot be more than gross weight.");
        return new ItemWeights(g, s, n);
    }
}
