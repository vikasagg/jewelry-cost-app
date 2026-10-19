package com.swarnos.sales.service;

import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;
import java.util.List;

/** A bill to price or save: items by id or tag, old metal in exchange, and the payments received. */
public record SaleCommand(Long customerId, String notes, List<Line> lines, List<Exchange> exchange, List<PaymentLeg> payments) {

    public record Line(Long itemId, String tagCode, BigDecimal discount) {}

    public record Exchange(String description, Metal metal, String purityCode, BigDecimal grossWt, BigDecimal netWt,
                           BigDecimal deductionPct) {}

    public record PaymentLeg(PaymentMode mode, BigDecimal amount, String reference) {}

    public List<Line> lines() {
        return lines == null ? List.of() : lines;
    }

    public List<Exchange> exchange() {
        return exchange == null ? List.of() : exchange;
    }

    public List<PaymentLeg> payments() {
        return payments == null ? List.of() : payments;
    }
}
