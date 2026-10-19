package com.swarnos.rates.infrastructure;

import com.swarnos.common.money.Decimals;
import com.swarnos.rates.domain.BaseRates;
import java.math.BigDecimal;
import java.util.concurrent.ThreadLocalRandom;
import org.springframework.stereotype.Component;

/** Simulated feed until the real provider is chosen (BRD O-1): moves the last rate by up to +/-0.5%. */
@Component
public class DemoRateProvider implements MetalRateProvider {
    private static final BaseRates DEFAULTS = new BaseRates(new BigDecimal("7500"), new BigDecimal("92"), new BigDecimal("3100"));

    @Override
    public String code() {
        return "DEMO";
    }

    @Override
    public LiveQuote fetch(LiveFeedConfig config, BaseRates last) {
        BaseRates base = last == null ? DEFAULTS : last;
        return new LiveQuote(new BaseRates(drift(base.gold24k()), drift(base.silver()), drift(base.platinum())),
                "DEMO (simulated feed)");
    }

    private static BigDecimal drift(BigDecimal v) {
        return Decimals.round(v.multiply(BigDecimal.valueOf(1 + ThreadLocalRandom.current().nextDouble(-0.005, 0.005))));
    }
}
