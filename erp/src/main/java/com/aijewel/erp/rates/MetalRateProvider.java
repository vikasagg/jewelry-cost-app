package com.aijewel.erp.rates;

import com.aijewel.erp.config.ConfigService;

/**
 * A live metal-rate source. It only ever produces a proposal; prices change
 * only after a person approves it (owner decision D-03).
 */
public interface MetalRateProvider {
    String code();

    LiveRates fetch(ConfigService config, LiveRates lastApproved);
}
