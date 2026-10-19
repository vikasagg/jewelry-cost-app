package com.swarnos.purchase.domain;

import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import java.math.BigDecimal;

/** Value, GST, total and what remains due after the payment legs. */
public record PurchaseTotals(BigDecimal taxable, BigDecimal gst, BigDecimal total, BigDecimal metalValuePaid, BigDecimal balanceDue) {
    /** Up to one rupee of over-payment is tolerated as rounding. */
    private static final BigDecimal TOLERANCE = BigDecimal.ONE;

    public static PurchaseTotals of(BigDecimal taxable, BigDecimal gstPct, PaymentLegs legs, BigDecimal metalValuePaid) {
        BigDecimal t = Decimals.round(taxable);
        BigDecimal gst = Decimals.percentOf(t, gstPct);
        BigDecimal total = Decimals.round(t.add(gst));
        BigDecimal paid = legs.cash().add(legs.bank()).add(Decimals.orZero(metalValuePaid));
        BigDecimal balance = Decimals.round(total.subtract(paid));
        if (balance.negate().compareTo(TOLERANCE) > 0) {
            throw BusinessException.validation("Payment (" + Decimals.round(paid) + ") is more than the purchase value (" + total + ").");
        }
        return new PurchaseTotals(t, gst, total, Decimals.orZero(metalValuePaid), balance);
    }
}
