package com.swarnos.rates.domain;

import com.swarnos.common.error.BusinessException;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

/** The approved rates a bill or valuation uses: lookup by metal and purity. */
public final class DailyRates {
    private final long rateSetId;
    private final Map<String, BigDecimal> rates;

    public DailyRates(long rateSetId, List<RateLine> lines) {
        this.rateSetId = rateSetId;
        this.rates = lines.stream().collect(Collectors.toMap(l -> key(l.metal(), l.purityCode()), RateLine::ratePerGram,
                (a, b) -> b));
    }

    public long rateSetId() {
        return rateSetId;
    }

    public Optional<BigDecimal> find(Metal metal, String purity) {
        return metal == null ? Optional.empty() : Optional.ofNullable(rates.get(key(metal, purity)));
    }

    public BigDecimal ratePerGram(Metal metal, String purity) {
        return find(metal, purity).orElseThrow(() ->
                BusinessException.validation("No rate for " + metal + " " + purity + " in today's rate set."));
    }

    private static String key(Metal metal, String purity) {
        return metal + "|" + purity;
    }
}
