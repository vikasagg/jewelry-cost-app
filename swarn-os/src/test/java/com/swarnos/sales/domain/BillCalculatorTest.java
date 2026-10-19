package com.swarnos.sales.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;

class BillCalculatorTest {
    private static QuotedLine line(String taxable, String discount, String gst) {
        BigDecimal t = new BigDecimal(taxable), g = new BigDecimal(gst);
        return new QuotedLine(1, "T1", "Chain", Metal.GOLD, "22K", 1, BigDecimal.ONE, BigDecimal.ONE, null, BigDecimal.ONE,
                BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO, new BigDecimal(discount), t, new BigDecimal("3"), g, t.add(g));
    }

    private static QuotedExchange exchange(String value) {
        return new QuotedExchange("Old", Metal.GOLD, "22K", BigDecimal.ONE, BigDecimal.ONE, BigDecimal.ONE, BigDecimal.ONE,
                BigDecimal.ZERO, new BigDecimal(value));
    }

    @Test
    void itemsLessExchange() {
        BillQuote q = BillCalculator.total(7, List.of(line("1000", "0", "30"), line("2000", "0", "60")), List.of(exchange("500.5")),
                RoundOff.NONE);
        assertThat(q.itemsTotal()).isEqualByComparingTo("3090.000");
        assertThat(q.gstTotal()).isEqualByComparingTo("90.000");
        assertThat(q.exchangeTotal()).isEqualByComparingTo("500.500");
        assertThat(q.netPayable()).isEqualByComparingTo("2589.500");
        assertThat(q.rateSetId()).isEqualTo(7);
    }

    @Test
    void roundsToRupeeWhenConfigured() {
        BillQuote q = BillCalculator.total(1, List.of(line("1000.6", "0", "0")), List.of(), RoundOff.RUPEE);
        assertThat(q.netPayable()).isEqualByComparingTo("1001.000");
        assertThat(q.roundOff()).isEqualByComparingTo("0.400");
    }

    @Test
    void exchangeCannotExceedItems() {
        assertThatThrownBy(() -> BillCalculator.total(1, List.of(line("100", "0", "3")), List.of(exchange("200")), RoundOff.NONE))
                .hasMessageContaining("exchange is worth more");
    }

    @Test
    void discountAboveTheLimitNeedsApproval() {
        BillQuote q = BillCalculator.total(1, List.of(line("900", "100", "27")), List.of(), RoundOff.NONE);
        assertThat(BillCalculator.discountNeedsApproval(q, new BigDecimal("5"))).isTrue();
        assertThat(BillCalculator.discountNeedsApproval(q, new BigDecimal("10"))).isFalse();
    }
}
