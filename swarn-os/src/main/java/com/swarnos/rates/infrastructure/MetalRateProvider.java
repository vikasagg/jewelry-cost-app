package com.swarnos.rates.infrastructure;

import com.swarnos.rates.domain.BaseRates;

/**
 * A live metal-rate source. It only produces a proposal; prices change only
 * after a person approves it (owner decision D-03).
 */
public interface MetalRateProvider {
    String code();

    LiveQuote fetch(LiveFeedConfig config, BaseRates lastApproved);
}
