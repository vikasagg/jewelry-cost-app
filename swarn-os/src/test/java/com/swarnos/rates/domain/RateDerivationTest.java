package com.swarnos.rates.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.swarnos.common.error.BusinessException;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.Purity;
import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;

class RateDerivationTest {
    private static Purity purity(Metal m, String code, String factor, String fineness) {
        return new Purity(0, m, code, new BigDecimal(factor), new BigDecimal(fineness), 0, true);
    }

    @Test
    void goldPuritiesFollowTheOwnersPercentages() {
        List<Purity> purities = List.of(purity(Metal.GOLD, "24K", "1", "0.999"), purity(Metal.GOLD, "22K", "0.92", "0.916"),
                purity(Metal.GOLD, "20K", "0.84", "0.833"), purity(Metal.GOLD, "18K", "0.76", "0.75"),
                purity(Metal.GOLD, "14K", "0.60", "0.585"), purity(Metal.GOLD, "9K", "0.40", "0.375"),
                purity(Metal.SILVER, "925", "0.925", "0.925"));
        DailyRates rates = new DailyRates(1, RateDerivation.derive(new BaseRates(new BigDecimal("7500"), new BigDecimal("92"),
                new BigDecimal("3100")), purities));
        assertThat(rates.ratePerGram(Metal.GOLD, "22K")).isEqualByComparingTo("6900.000");
        assertThat(rates.ratePerGram(Metal.GOLD, "20K")).isEqualByComparingTo("6300.000");
        assertThat(rates.ratePerGram(Metal.GOLD, "18K")).isEqualByComparingTo("5700.000");
        assertThat(rates.ratePerGram(Metal.GOLD, "14K")).isEqualByComparingTo("4500.000");
        assertThat(rates.ratePerGram(Metal.GOLD, "9K")).isEqualByComparingTo("3000.000");
        assertThat(rates.ratePerGram(Metal.SILVER, "925")).isEqualByComparingTo("85.100");
        assertThatThrownBy(() -> rates.ratePerGram(Metal.PLATINUM, "950")).isInstanceOf(BusinessException.class);
    }

    @Test
    void baseRatesMustBePositive() {
        assertThatThrownBy(() -> new BaseRates(new BigDecimal("7500"), BigDecimal.ZERO, new BigDecimal("1")).requireAllPositive())
                .isInstanceOf(BusinessException.class);
    }

    @Test
    void oldMetalValuationDeductsAndComputesFineWeight() {
        MetalValuation v = MetalValuation.of(new BigDecimal("3.900"), new BigDecimal("6900"), new BigDecimal("2"), new BigDecimal("0.916"));
        assertThat(v.value()).isEqualByComparingTo("26371.800");
        assertThat(v.fineWeight()).isEqualByComparingTo("3.572");
    }
}
