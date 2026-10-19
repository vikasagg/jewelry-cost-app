package com.swarnos.purchase.api.dto;

import com.swarnos.inventory.domain.PurchaseClass;
import com.swarnos.purchase.domain.PaymentLegs;
import com.swarnos.purchase.domain.PurchaseKind;
import com.swarnos.purchase.service.PurchaseCommand;
import java.math.BigDecimal;
import java.util.List;

public record PurchaseRequest(Long partyId, PurchaseKind purchaseKind, String gstInvoiceNo, BigDecimal gstPct,
                              PurchaseClass purchaseClass, String notes, List<PurchaseLineRequest> lines,
                              PurchasePaymentRequest payment) {

    public PurchaseCommand toCommand() {
        List<PurchaseLineRequest> l = lines == null ? List.of() : lines;
        return new PurchaseCommand(partyId, purchaseKind, gstInvoiceNo, gstPct, purchaseClass, notes,
                l.stream().map(PurchaseLineRequest::toNewItem).toList(), l.stream().map(PurchaseLineRequest::toOldMetal).toList(),
                payment == null ? PaymentLegs.none() : payment.toLegs());
    }
}
