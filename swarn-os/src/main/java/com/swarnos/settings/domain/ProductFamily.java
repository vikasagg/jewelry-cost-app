package com.swarnos.settings.domain;

/** Product families from BRD §3; each implies its metal (none for gifting). */
public enum ProductFamily {
    GOLD(Metal.GOLD), DIAMOND(Metal.GOLD), PLATINUM(Metal.PLATINUM), SILVER(Metal.SILVER),
    SILVER_ORNAMENT(Metal.SILVER), GIFTING(null);

    private final Metal metal;

    ProductFamily(Metal metal) {
        this.metal = metal;
    }

    public Metal metal() {
        return metal;
    }

    public PricingMode pricingMode() {
        return metal == null ? PricingMode.FIXED : PricingMode.METAL;
    }
}
