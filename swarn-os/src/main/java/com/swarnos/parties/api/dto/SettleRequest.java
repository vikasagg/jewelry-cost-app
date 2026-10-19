package com.swarnos.parties.api.dto;

import com.swarnos.accounting.domain.Direction;
import com.swarnos.accounting.domain.PaymentMode;
import java.math.BigDecimal;

public record SettleRequest(Direction direction, PaymentMode mode, BigDecimal amount, String reference) {}
