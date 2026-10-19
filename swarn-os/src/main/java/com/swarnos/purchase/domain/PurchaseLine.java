package com.swarnos.purchase.domain;

import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;

/** A purchase line; {@code tagCode} is filled when reading (the item it created). */
public record PurchaseLine(long id, long purchaseId, Long itemId, String description, Metal metal, String purityCode,
                           BigDecimal grossWt, BigDecimal netWt, BigDecimal fineWt, BigDecimal rate, BigDecimal deductionPct,
                           int quantity, BigDecimal amount, String tagCode) {}
