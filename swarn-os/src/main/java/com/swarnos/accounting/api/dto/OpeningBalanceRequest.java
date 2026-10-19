package com.swarnos.accounting.api.dto;

import com.swarnos.accounting.domain.Book;
import java.math.BigDecimal;

public record OpeningBalanceRequest(Book book, BigDecimal amount) {}
