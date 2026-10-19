package com.swarnos.purchase.domain;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.swarnos.inventory.domain.PurchaseClass;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record Purchase(long id, String purchaseNo, LocalDate businessDate, Long partyId, PurchaseKind purchaseKind,
                       SettlementMode paymentMode, String gstInvoiceNo, BigDecimal taxableAmount, BigDecimal gstAmount,
                       BigDecimal totalAmount, BigDecimal cashPaid, BigDecimal bankPaid, String bankRef,
                       BigDecimal goldFinePaid, BigDecimal silverFinePaid, BigDecimal metalValuePaid, BigDecimal balanceDue,
                       PurchaseClass purchaseClass, Long rateSetId, String notes, String createdBy, Instant createdAt) {

    /** The same purchase without its Seen/Unseen class, for roles that may not see it. */
    public Purchase withoutClass() {
        return new Purchase(id, purchaseNo, businessDate, partyId, purchaseKind, paymentMode, gstInvoiceNo, taxableAmount,
                gstAmount, totalAmount, cashPaid, bankPaid, bankRef, goldFinePaid, silverFinePaid, metalValuePaid, balanceDue,
                null, rateSetId, notes, createdBy, createdAt);
    }
}
