package com.swarnos.purchase.domain;

import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

/** The legs a purchase is paid with: cash, bank, fine gold and fine silver. */
public record PaymentLegs(BigDecimal cash, BigDecimal bank, PaymentMode bankMode, String bankRef, BigDecimal goldFine,
                          BigDecimal silverFine) {

    public PaymentLegs {
        cash = Decimals.orZero(cash);
        bank = Decimals.orZero(bank);
        goldFine = Decimals.orZero(goldFine);
        silverFine = Decimals.orZero(silverFine);
        bankMode = bankMode == null || bankMode == PaymentMode.CASH ? PaymentMode.BANK : bankMode;
        bankRef = bankRef == null || bankRef.isBlank() ? null : bankRef.trim();
        if (cash.signum() < 0 || bank.signum() < 0 || goldFine.signum() < 0 || silverFine.signum() < 0) {
            throw BusinessException.validation("Payment amounts cannot be negative.");
        }
    }

    public static PaymentLegs none() {
        return new PaymentLegs(null, null, null, null, null, null);
    }

    public boolean anyCash() {
        return cash.signum() > 0;
    }

    public boolean settlesInMetal() {
        return goldFine.signum() > 0 || silverFine.signum() > 0;
    }

    public SettlementMode mode() {
        List<SettlementMode> legs = new ArrayList<>();
        if (cash.signum() > 0) legs.add(SettlementMode.CASH);
        if (bank.signum() > 0) legs.add(SettlementMode.BANK);
        if (goldFine.signum() > 0) legs.add(SettlementMode.GOLD);
        if (silverFine.signum() > 0) legs.add(SettlementMode.SILVER);
        if (legs.isEmpty()) return SettlementMode.CREDIT;
        return legs.size() == 1 ? legs.get(0) : SettlementMode.MIXED;
    }
}
