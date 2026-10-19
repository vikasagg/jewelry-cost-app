package com.swarnos.sales.domain;

import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;

/** Bill totals: items (with GST) less exchange, optionally rounded to the rupee. */
public final class BillCalculator {
    private BillCalculator() {}

    public static BillQuote total(long rateSetId, List<QuotedLine> lines, List<QuotedExchange> exchange, RoundOff roundOff) {
        BigDecimal items = Decimals.ZERO, discount = Decimals.ZERO, taxable = Decimals.ZERO, gst = Decimals.ZERO;
        for (QuotedLine l : lines) {
            items = items.add(l.lineTotal());
            discount = discount.add(l.discount());
            taxable = taxable.add(l.taxable());
            gst = gst.add(l.gst());
        }
        BigDecimal exchangeTotal = exchange.stream().map(QuotedExchange::value).reduce(Decimals.ZERO, BigDecimal::add);
        BigDecimal beforeRound = Decimals.round(items.subtract(exchangeTotal));
        BigDecimal net = roundOff == RoundOff.RUPEE ? Decimals.round(beforeRound.setScale(0, RoundingMode.HALF_UP)) : beforeRound;
        if (net.signum() < 0) {
            throw BusinessException.validation("The exchange is worth more than the items. Record the extra as an old-metal purchase.");
        }
        return new BillQuote(rateSetId, lines, exchange, Decimals.round(items), Decimals.round(discount), Decimals.round(taxable),
                Decimals.round(gst), Decimals.round(exchangeTotal), Decimals.round(net.subtract(beforeRound)), net,
                Decimals.round(taxable.add(discount)));
    }

    /** True when the discount is above the share a salesperson may give on their own. */
    public static boolean discountNeedsApproval(BillQuote quote, BigDecimal maxPct) {
        return quote.discount().signum() > 0 && Decimals.percentOf(quote.valueBeforeDiscount(), maxPct).compareTo(quote.discount()) < 0;
    }
}
