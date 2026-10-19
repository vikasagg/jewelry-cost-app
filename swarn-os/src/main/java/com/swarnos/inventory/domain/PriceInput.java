package com.swarnos.inventory.domain;

import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.PricingMode;
import java.math.BigDecimal;

/** Everything needed to price one item at a given rate. */
public record PriceInput(PricingMode pricingMode, BigDecimal netWt, BigDecimal ratePerGram, MakingType makingType,
                         BigDecimal makingValue, BigDecimal wastagePct, BigDecimal stoneValue, BigDecimal fixedPrice,
                         int quantity, BigDecimal gstPct) {

    public static PriceInput of(ItemListing l, BigDecimal ratePerGram) {
        return new PriceInput(l.pricingMode(), l.item().netWt(), ratePerGram, l.makingType(), l.makingValue(), l.wastagePct(),
                l.stoneValue(), l.item().fixedPrice(), l.item().quantity(), l.gstPct());
    }
}
