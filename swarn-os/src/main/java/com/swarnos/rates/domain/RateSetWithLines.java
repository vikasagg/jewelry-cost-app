package com.swarnos.rates.domain;

import com.fasterxml.jackson.annotation.JsonUnwrapped;
import java.util.List;

public record RateSetWithLines(@JsonUnwrapped RateSet rateSet, List<RateLine> lines) {}
