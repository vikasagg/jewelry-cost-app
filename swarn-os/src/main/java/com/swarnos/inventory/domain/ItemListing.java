package com.swarnos.inventory.domain;

import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.PricingMode;
import com.swarnos.settings.domain.ProductFamily;
import com.swarnos.settings.domain.Tracking;
import java.math.BigDecimal;

/** An item with what is needed to show and price it: category rules, names and stone totals. */
public record ItemListing(Item item, String categoryCode, String categoryName, ProductFamily family, PricingMode pricingMode,
                          Tracking tracking, BigDecimal gstPct, MakingType categoryMakingType, BigDecimal categoryMakingValue,
                          BigDecimal categoryWastagePct, String locationName, String vendorName, BigDecimal stoneValue,
                          BigDecimal stoneCarat, String stoneType) {

    public MakingType makingType() {
        return item.makingType() != null ? item.makingType() : categoryMakingType;
    }

    public BigDecimal makingValue() {
        return item.makingValue() != null ? item.makingValue() : categoryMakingValue;
    }

    public BigDecimal wastagePct() {
        return item.wastagePct() != null ? item.wastagePct() : categoryWastagePct;
    }
}
