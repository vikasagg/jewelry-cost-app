package com.swarnos.sales.api.dto;

import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.sales.service.SaleCommand;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;
import java.util.List;

public record SaleRequest(Long customerId, String notes, List<LineRequest> lines, List<ExchangeRequest> exchange,
                          List<PaymentRequest> payments) {

    public record LineRequest(Long itemId, String tagCode, BigDecimal discount) {}

    public record ExchangeRequest(String description, Metal metal, String purityCode, BigDecimal grossWt, BigDecimal netWt,
                                  BigDecimal deductionPct) {}

    public record PaymentRequest(PaymentMode mode, BigDecimal amount, String reference) {}

    public SaleCommand toCommand() {
        return new SaleCommand(customerId, notes,
                lines == null ? List.of() : lines.stream().map(l -> new SaleCommand.Line(l.itemId(), l.tagCode(), l.discount())).toList(),
                exchange == null ? List.of() : exchange.stream().map(x -> new SaleCommand.Exchange(x.description(), x.metal(),
                        x.purityCode(), x.grossWt(), x.netWt(), x.deductionPct())).toList(),
                payments == null ? List.of() : payments.stream().map(p -> new SaleCommand.PaymentLeg(p.mode(), p.amount(), p.reference()))
                        .toList());
    }
}
