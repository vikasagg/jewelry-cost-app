package com.swarnos.rates;

import com.swarnos.common.Num;
import com.swarnos.config.ConfigService;
import java.math.BigDecimal;
import java.util.concurrent.ThreadLocalRandom;
import org.springframework.stereotype.Component;

/**
 * Simulated feed for the prototype until the real provider is chosen (BRD
 * open item O-1): moves the last approved rate by up to +/-0.5%.
 */
@Component
public class DemoRateProvider implements MetalRateProvider {
    @Override
    public String code() {
        return "DEMO";
    }

    @Override
    public LiveRates fetch(ConfigService config, LiveRates last) {
        BigDecimal gold = last == null ? new BigDecimal("7500") : last.gold24k();
        BigDecimal silver = last == null ? new BigDecimal("92") : last.silver();
        BigDecimal platinum = last == null ? new BigDecimal("3100") : last.platinum();
        return new LiveRates(drift(gold), drift(silver), drift(platinum), "DEMO (simulated feed)");
    }

    private static BigDecimal drift(BigDecimal v) {
        double change = ThreadLocalRandom.current().nextDouble(-0.005, 0.005);
        return Num.r(v.multiply(BigDecimal.valueOf(1 + change)));
    }
}
