package com.swarnos.inventory.domain;

import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import com.swarnos.rates.domain.DailyRates;
import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.PricingMode;
import java.math.BigDecimal;
import java.util.Optional;

/**
 * Selling price of one item (BRD §6.3): metal value = net weight x purity rate;
 * wastage = metal value x wastage %; making per gram, % of metal value or fixed;
 * plus stone value; less discount; GST on the taxable value. 3 decimals throughout.
 */
public final class PricingEngine {
    private PricingEngine() {}

    public static PriceBreakdown price(PriceInput in, BigDecimal discount) {
        BigDecimal disc = Decimals.orZero(discount);
        if (disc.signum() < 0) throw BusinessException.validation("Discount cannot be negative.");

        BigDecimal rate = Decimals.ZERO, metal = Decimals.ZERO, wastage = Decimals.ZERO, making = Decimals.ZERO;
        BigDecimal stones = Decimals.orZero(in.stoneValue());
        BigDecimal gross;
        if (in.pricingMode() == PricingMode.FIXED) {
            gross = Decimals.multiply(in.fixedPrice(), BigDecimal.valueOf(Math.max(1, in.quantity())));
            stones = Decimals.ZERO;
        } else {
            rate = Decimals.orZero(in.ratePerGram());
            metal = Decimals.multiply(in.netWt(), rate);
            wastage = Decimals.percentOf(metal, in.wastagePct());
            making = switch (in.makingType() == null ? MakingType.PER_GRAM : in.makingType()) {
                case PERCENT -> Decimals.percentOf(metal, in.makingValue());
                case FIXED -> Decimals.orZero(in.makingValue());
                case PER_GRAM -> Decimals.multiply(in.netWt(), in.makingValue());
            };
            gross = metal.add(wastage).add(making).add(stones);
        }
        if (disc.compareTo(gross) > 0) throw BusinessException.validation("Discount is more than the item value.");
        BigDecimal taxable = Decimals.round(gross.subtract(disc));
        BigDecimal gst = Decimals.percentOf(taxable, in.gstPct());
        return new PriceBreakdown(rate, metal, wastage, making, stones, disc, taxable, Decimals.orZero(in.gstPct()), gst,
                Decimals.round(taxable.add(gst)));
    }

    /** Price at today's rates, or empty when a metal item has no approved rate yet. */
    public static Optional<PriceBreakdown> priceAt(ItemListing item, Optional<DailyRates> rates) {
        if (item.pricingMode() == PricingMode.FIXED) return Optional.of(price(PriceInput.of(item, Decimals.ZERO), null));
        return rates.flatMap(r -> r.find(item.item().metal(), item.item().purityCode()))
                .map(rate -> price(PriceInput.of(item, rate), null));
    }
}
