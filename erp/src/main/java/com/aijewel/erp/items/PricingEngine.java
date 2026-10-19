package com.aijewel.erp.items;

import com.aijewel.erp.common.ApiException;
import com.aijewel.erp.common.Num;
import java.math.BigDecimal;

/**
 * Selling price of one item (BRD §6.3):
 * metal value = net weight x purity rate; wastage = metal value x wastage %;
 * making per gram, % of metal value, or fixed; plus stone value; less discount;
 * GST on the taxable value. Every step is rounded to 3 decimals.
 */
public final class PricingEngine {
    private PricingEngine() {}

    public static PriceBreakdown price(PriceInput in, BigDecimal discount) {
        BigDecimal disc = Num.r(discount == null ? BigDecimal.ZERO : discount);
        if (disc.signum() < 0) throw ApiException.bad("Discount cannot be negative.");

        BigDecimal metal = Num.ZERO, wastage = Num.ZERO, making = Num.ZERO, rate = Num.ZERO;
        BigDecimal stones = Num.r(in.stoneValue());
        BigDecimal gross;
        if ("FIXED".equals(in.pricingMode())) {
            gross = Num.mul(Num.r(in.fixedPrice()), BigDecimal.valueOf(Math.max(1, in.quantity())));
            stones = Num.ZERO;
        } else {
            rate = Num.r(in.ratePerGram());
            metal = Num.mul(Num.r(in.netWt()), rate);
            wastage = Num.pct(metal, Num.r(in.wastagePct()));
            BigDecimal mv = Num.r(in.makingValue());
            making = switch (in.makingType() == null ? "PER_GRAM" : in.makingType()) {
                case "PERCENT" -> Num.pct(metal, mv);
                case "FIXED" -> mv;
                default -> Num.mul(Num.r(in.netWt()), mv);
            };
            gross = metal.add(wastage).add(making).add(stones);
        }
        if (disc.compareTo(gross) > 0) throw ApiException.bad("Discount is more than the item value.");
        BigDecimal taxable = Num.r(gross.subtract(disc));
        BigDecimal gstPct = Num.r(in.gstPct());
        BigDecimal gst = Num.pct(taxable, gstPct);
        return new PriceBreakdown(rate, metal, wastage, making, stones, disc, taxable, gstPct, gst, Num.r(taxable.add(gst)));
    }
}
