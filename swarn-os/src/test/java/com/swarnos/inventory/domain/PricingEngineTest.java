package com.swarnos.inventory.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.swarnos.common.error.BusinessException;
import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.PricingMode;
import java.math.BigDecimal;
import org.junit.jupiter.api.Test;

class PricingEngineTest {

    private static PriceInput metal(String net, String rate, MakingType makingType, String making, String wastage, String stones) {
        return new PriceInput(PricingMode.METAL, new BigDecimal(net), new BigDecimal(rate), makingType, new BigDecimal(making),
                new BigDecimal(wastage), new BigDecimal(stones), null, 1, new BigDecimal("3"));
    }

    @Test
    void brdWorkedExample22kChain() {
        // BRD 6.3: 22K chain, net 10.250 g at 6,900/g, making 12%, GST 3% -> 81,588.360
        PriceBreakdown p = PricingEngine.price(metal("10.250", "6900", MakingType.PERCENT, "12", "0", "0"), BigDecimal.ZERO);
        assertThat(p.metalValue()).isEqualByComparingTo("70725.000");
        assertThat(p.makingValue()).isEqualByComparingTo("8487.000");
        assertThat(p.taxable()).isEqualByComparingTo("79212.000");
        assertThat(p.gst()).isEqualByComparingTo("2376.360");
        assertThat(p.total()).isEqualByComparingTo("81588.360");
        assertThat(p.total().scale()).isEqualTo(3);
    }

    @Test
    void perGramMakingWastageStonesAndDiscount() {
        PriceBreakdown p = PricingEngine.price(metal("3.140", "5700", MakingType.PER_GRAM, "1500", "2", "21000"), new BigDecimal("1000"));
        assertThat(p.metalValue()).isEqualByComparingTo("17898.000");
        assertThat(p.wastageValue()).isEqualByComparingTo("357.960");
        assertThat(p.makingValue()).isEqualByComparingTo("4710.000");
        assertThat(p.taxable()).isEqualByComparingTo("42965.960");
        assertThat(p.gst()).isEqualByComparingTo("1288.979");
        assertThat(p.total()).isEqualByComparingTo("44254.939");
    }

    @Test
    void fixedPriceGiftingUsesMrpTimesQuantity() {
        PriceInput gift = new PriceInput(PricingMode.FIXED, BigDecimal.ZERO, BigDecimal.ZERO, MakingType.FIXED, BigDecimal.ZERO,
                BigDecimal.ZERO, BigDecimal.ZERO, new BigDecimal("650"), 4, new BigDecimal("18"));
        PriceBreakdown p = PricingEngine.price(gift, BigDecimal.ZERO);
        assertThat(p.taxable()).isEqualByComparingTo("2600.000");
        assertThat(p.total()).isEqualByComparingTo("3068.000");
    }

    @Test
    void discountCannotExceedValueOrBeNegative() {
        assertThatThrownBy(() -> PricingEngine.price(metal("1", "100", MakingType.FIXED, "0", "0", "0"), new BigDecimal("101")))
                .isInstanceOf(BusinessException.class);
        assertThatThrownBy(() -> PricingEngine.price(metal("1", "100", MakingType.FIXED, "0", "0", "0"), new BigDecimal("-1")))
                .isInstanceOf(BusinessException.class);
    }

    @Test
    void stoneWeightDefaultsFromCaratsAndNetFromGross() {
        ItemWeights w = ItemWeights.resolve(new BigDecimal("3.200"), null, null,
                java.util.List.of(new NewStone("DIAMOND", 1, new BigDecimal("0.30"), BigDecimal.ZERO, null, null, null, null)));
        assertThat(w.stone()).isEqualByComparingTo("0.060");
        assertThat(w.net()).isEqualByComparingTo("3.140");
        assertThatThrownBy(() -> ItemWeights.resolve(new BigDecimal("2"), null, new BigDecimal("3"), java.util.List.of()))
                .hasMessageContaining("Net weight cannot be more");
    }

    @Test
    void purchaseClassRule() {
        assertThat(PurchaseClass.classify(true, false)).isEqualTo(PurchaseClass.SEEN);
        assertThat(PurchaseClass.classify(true, true)).isEqualTo(PurchaseClass.UNSEEN);
        assertThat(PurchaseClass.classify(false, false)).isEqualTo(PurchaseClass.UNSEEN);
    }
}
