package com.swarnos.rates.domain;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

/** One day's base rates, entered by hand or proposed from a live feed, and their approval. */
public record RateSet(long id, LocalDate businessDate, RateSource source, String provider,
                      @JsonProperty("gold_24k") BigDecimal gold24k, BigDecimal silverBase, BigDecimal platinumBase,
                      RateSetStatus status, String enteredBy, Instant enteredAt, String approvedBy, Instant approvedAt,
                      String note) {

    public BaseRates baseRates() {
        return new BaseRates(gold24k, silverBase, platinumBase);
    }
}
