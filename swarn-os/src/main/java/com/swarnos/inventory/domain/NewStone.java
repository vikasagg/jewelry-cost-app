package com.swarnos.inventory.domain;

import com.swarnos.common.money.Decimals;
import java.math.BigDecimal;

/** A stone line of a new item; value defaults to carat x rate per carat. */
public record NewStone(String stoneType, Integer pieces, BigDecimal carat, BigDecimal ratePerCarat, BigDecimal value,
                       String clarity, String colour, String certificate) {

    public boolean isPresent() {
        return Decimals.isPositive(carat) || Decimals.isPositive(value);
    }

    public String type() {
        return stoneType == null || stoneType.isBlank() ? "DIAMOND" : stoneType.trim().toUpperCase();
    }

    public BigDecimal resolvedValue() {
        return value != null ? Decimals.round(value) : Decimals.multiply(carat, ratePerCarat);
    }
}
