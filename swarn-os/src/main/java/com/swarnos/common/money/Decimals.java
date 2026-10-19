package com.swarnos.common.money;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** Money, weight and rate arithmetic: 3 decimal places, half-up (owner decision D-04). */
public final class Decimals {
    public static final int SCALE = 3;
    public static final BigDecimal ZERO = BigDecimal.ZERO.setScale(SCALE);
    private static final BigDecimal HUNDRED = BigDecimal.valueOf(100);

    private Decimals() {}

    public static BigDecimal round(BigDecimal v) {
        return v == null ? ZERO : v.setScale(SCALE, RoundingMode.HALF_UP);
    }

    /** Null stays null: used for optional values such as "no limit". */
    public static BigDecimal roundOrNull(BigDecimal v) {
        return v == null ? null : round(v);
    }

    public static BigDecimal orZero(BigDecimal v) {
        return round(v);
    }

    public static BigDecimal of(String v) {
        return round(new BigDecimal(v));
    }

    public static BigDecimal multiply(BigDecimal a, BigDecimal b) {
        return round(orZero(a).multiply(orZero(b)));
    }

    /** base x pct / 100 */
    public static BigDecimal percentOf(BigDecimal base, BigDecimal pct) {
        return round(orZero(base).multiply(orZero(pct)).divide(HUNDRED, 10, RoundingMode.HALF_UP));
    }

    public static BigDecimal sum(BigDecimal a, BigDecimal b) {
        return round(orZero(a).add(orZero(b)));
    }

    public static boolean isPositive(BigDecimal v) {
        return v != null && v.signum() > 0;
    }

    public static boolean isZero(BigDecimal v) {
        return v == null || v.signum() == 0;
    }
}
