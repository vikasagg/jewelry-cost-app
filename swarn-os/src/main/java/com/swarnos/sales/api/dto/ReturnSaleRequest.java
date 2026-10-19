package com.swarnos.sales.api.dto;

import com.swarnos.accounting.domain.PaymentMode;

public record ReturnSaleRequest(String reason, PaymentMode refundMode) {}
