package com.swarnos.inventory.domain;

import java.math.BigDecimal;

public record Stone(long id, long itemId, String stoneType, int pieces, BigDecimal carat, BigDecimal ratePerCarat,
                    BigDecimal stoneValue, String clarity, String colour, String certificate) {}
