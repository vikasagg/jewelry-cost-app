package com.swarnos.settings.api.dto;

import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;

public record PriceFactorRequest(@NotNull BigDecimal priceFactor) {}
