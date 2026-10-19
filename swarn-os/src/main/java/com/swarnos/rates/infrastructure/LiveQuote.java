package com.swarnos.rates.infrastructure;

import com.swarnos.rates.domain.BaseRates;

public record LiveQuote(BaseRates rates, String provider) {}
