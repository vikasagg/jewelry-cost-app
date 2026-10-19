package com.swarnos.sales.domain;

import com.fasterxml.jackson.annotation.JsonIgnore;
import java.math.BigDecimal;
import java.util.List;

/** The full calculation of a bill, shown live while billing and saved as the sale. */
public record BillQuote(long rateSetId, List<QuotedLine> lines, List<QuotedExchange> exchange, BigDecimal itemsTotal,
                        BigDecimal discount, BigDecimal taxableTotal, BigDecimal gstTotal, BigDecimal exchangeTotal,
                        BigDecimal roundOff, BigDecimal netPayable, @JsonIgnore BigDecimal valueBeforeDiscount) {}
