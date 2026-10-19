package com.swarnos.tally.domain;

import java.math.BigDecimal;

/** Expected vs physical pieces and net weight of one category (BRD §5.2 step 4). */
public record CategoryCount(String code, String name, long expected, long physical, BigDecimal expectedWt, BigDecimal physicalWt) {}
