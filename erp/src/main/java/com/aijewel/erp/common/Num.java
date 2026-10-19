package com.aijewel.erp.common;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** Money, weight and rate arithmetic: 3 decimal places, half-up (owner decision D-04). */
public final class Num {
    public static final int SCALE = 3;
    public static final BigDecimal ZERO = BigDecimal.ZERO.setScale(SCALE);
    private static final BigDecimal HUNDRED = BigDecimal.valueOf(100);

    private Num() {}

    public static BigDecimal r(BigDecimal v) {
        return v == null ? ZERO : v.setScale(SCALE, RoundingMode.HALF_UP);
    }

    /** Reads a value from a JSON body or a database row; null or blank becomes zero. */
    public static BigDecimal of(Object o) {
        if (o == null) return ZERO;
        if (o instanceof BigDecimal b) return r(b);
        if (o instanceof Number n) return r(new BigDecimal(n.toString()));
        String s = o.toString().trim().replace(",", "");
        if (s.isEmpty()) return ZERO;
        try {
            return r(new BigDecimal(s));
        } catch (NumberFormatException e) {
            throw ApiException.bad("Not a number: " + o);
        }
    }

    /** Like {@link #of} but keeps null for "not set" (blank config limits). */
    public static BigDecimal ofNullable(Object o) {
        if (o == null || o.toString().isBlank()) return null;
        return of(o);
    }

    public static BigDecimal mul(BigDecimal a, BigDecimal b) {
        return r(a.multiply(b));
    }

    /** base x pct / 100 */
    public static BigDecimal pct(BigDecimal base, BigDecimal pct) {
        return r(base.multiply(pct).divide(HUNDRED, 10, RoundingMode.HALF_UP));
    }

    public static BigDecimal div(BigDecimal a, BigDecimal b) {
        if (b.signum() == 0) return ZERO;
        return a.divide(b, SCALE, RoundingMode.HALF_UP);
    }

    public static boolean positive(BigDecimal v) {
        return v != null && v.signum() > 0;
    }
}
