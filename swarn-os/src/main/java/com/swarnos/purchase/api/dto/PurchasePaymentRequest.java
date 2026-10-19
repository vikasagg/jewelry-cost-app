package com.swarnos.purchase.api.dto;

import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.purchase.domain.PaymentLegs;
import java.math.BigDecimal;

/** Payment legs: cash, bank (BANK/UPI/CHEQUE), fine gold grams and fine silver grams. */
public record PurchasePaymentRequest(BigDecimal cash, BigDecimal bank, PaymentMode bankMode, String bankRef,
                                     BigDecimal goldFine, BigDecimal silverFine) {

    public PaymentLegs toLegs() {
        return new PaymentLegs(cash, bank, bankMode, bankRef, goldFine, silverFine);
    }
}
