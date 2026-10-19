package com.swarnos.rates.domain;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;

/** Selling rate per gram for one metal and purity. */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record RateLine(Metal metal, String purityCode, BigDecimal ratePerGram, BigDecimal priceFactor) {}
