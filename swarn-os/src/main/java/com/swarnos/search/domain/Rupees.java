package com.swarnos.search.domain;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** Rupees with Indian digit grouping for spoken and written answers, e.g. ₹1,15,677. */
public final class Rupees {
    private Rupees() {}

    public static String format(BigDecimal v) {
        String digits = v.setScale(0, RoundingMode.HALF_UP).abs().toPlainString();
        StringBuilder out = new StringBuilder();
        int n = digits.length();
        for (int i = 0; i < n; i++) {
            out.append(digits.charAt(i));
            int left = n - i - 1;
            if (left > 0 && (left == 3 || (left > 3 && (left - 3) % 2 == 0))) out.append(',');
        }
        return (v.signum() < 0 ? "-₹" : "₹") + out;
    }
}
