package com.swarnos.sales.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonUnwrapped;
import com.swarnos.accounting.domain.Payment;
import com.swarnos.rates.domain.RateSetWithLines;
import com.swarnos.sales.domain.ExchangeLine;
import com.swarnos.sales.domain.Sale;
import com.swarnos.sales.domain.SaleLine;
import com.swarnos.sales.domain.SaleView;
import com.swarnos.sales.service.SaleService;
import com.swarnos.settings.domain.ShopProfile;
import java.util.List;

/** A bill: summary in lists; with lines, exchange, payments, rate and shop on the invoice. */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record SaleResponse(@JsonUnwrapped Sale sale, String customerName, String customerPhone, String customerAddress,
                           String customerGstin, String customerPan, Long itemCount, List<SaleLine> lines,
                           List<ExchangeLine> exchange, List<Payment> payments, RateSetWithLines rateSet, ShopProfile shop,
                           List<String> warnings) {

    public static SaleResponse summary(SaleView v) {
        return new SaleResponse(v.sale(), v.customerName(), v.customerPhone(), null, null, null, v.itemCount(), null, null,
                null, null, null, null);
    }

    public static SaleResponse of(SaleService.SaleDetail d, List<String> warnings) {
        SaleView v = d.view();
        return new SaleResponse(v.sale(), v.customerName(), v.customerPhone(), v.customerAddress(), v.customerGstin(),
                v.customerPan(), v.itemCount(), d.lines(), d.exchange(), d.payments(), d.rateSet(), d.shop(), warnings);
    }
}
