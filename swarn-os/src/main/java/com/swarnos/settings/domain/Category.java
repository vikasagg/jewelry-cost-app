package com.swarnos.settings.domain;

import java.math.BigDecimal;

public record Category(long id, String code, String name, ProductFamily family, Metal metal, PricingMode pricingMode,
                       Tracking tracking, String tagType, MakingType makingType, BigDecimal makingValue,
                       BigDecimal wastagePct, BigDecimal gstPct, boolean active) {

    public boolean isFixedPrice() {
        return pricingMode == PricingMode.FIXED;
    }
}
