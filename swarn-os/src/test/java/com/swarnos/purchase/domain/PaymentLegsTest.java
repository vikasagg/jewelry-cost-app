package com.swarnos.purchase.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.swarnos.common.error.BusinessException;
import java.math.BigDecimal;
import org.junit.jupiter.api.Test;

class PaymentLegsTest {
    private static PaymentLegs legs(String cash, String bank, String gold, String silver) {
        return new PaymentLegs(new BigDecimal(cash), new BigDecimal(bank), null, null, new BigDecimal(gold), new BigDecimal(silver));
    }

    @Test
    void settlementModeFollowsTheLegsUsed() {
        assertThat(legs("100", "0", "0", "0").mode()).isEqualTo(SettlementMode.CASH);
        assertThat(legs("0", "100", "0", "0").mode()).isEqualTo(SettlementMode.BANK);
        assertThat(legs("0", "0", "5", "0").mode()).isEqualTo(SettlementMode.GOLD);
        assertThat(legs("0", "0", "0", "50").mode()).isEqualTo(SettlementMode.SILVER);
        assertThat(legs("0", "100", "5", "0").mode()).isEqualTo(SettlementMode.MIXED);
        assertThat(PaymentLegs.none().mode()).isEqualTo(SettlementMode.CREDIT);
    }

    @Test
    void negativeLegsAreRejected() {
        assertThatThrownBy(() -> legs("-1", "0", "0", "0")).isInstanceOf(BusinessException.class);
    }

    @Test
    void totalsAddGstAndLeaveTheRestDue() {
        PurchaseTotals t = PurchaseTotals.of(new BigDecimal("57500"), new BigDecimal("3"), legs("0", "20145", "5", "0"),
                new BigDecimal("37500"));
        assertThat(t.gst()).isEqualByComparingTo("1725.000");
        assertThat(t.total()).isEqualByComparingTo("59225.000");
        assertThat(t.balanceDue()).isEqualByComparingTo("1580.000");
    }

    @Test
    void overpaymentIsRejected() {
        assertThatThrownBy(() -> PurchaseTotals.of(new BigDecimal("1000"), BigDecimal.ZERO, legs("1500", "0", "0", "0"), BigDecimal.ZERO))
                .hasMessageContaining("more than the purchase value");
    }
}
