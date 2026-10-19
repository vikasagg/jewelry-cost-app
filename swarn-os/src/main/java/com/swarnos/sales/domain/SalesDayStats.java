package com.swarnos.sales.domain;

import java.math.BigDecimal;

public record SalesDayStats(long bills, BigDecimal net, BigDecimal gst, long pieces) {}
