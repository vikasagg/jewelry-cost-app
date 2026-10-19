package com.swarnos.sales.domain;

/** Bill rounding: none (3 decimals) or to the nearest rupee. */
public enum RoundOff {
    NONE, RUPEE;

    public static RoundOff fromSetting(String value) {
        return "RUPEE".equalsIgnoreCase(value) ? RUPEE : NONE;
    }
}
