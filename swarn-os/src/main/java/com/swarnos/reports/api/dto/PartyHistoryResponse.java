package com.swarnos.reports.api.dto;

import com.fasterxml.jackson.annotation.JsonUnwrapped;
import com.swarnos.accounting.domain.LedgerEntry;
import com.swarnos.parties.api.dto.PartyResponse;
import com.swarnos.parties.domain.Party;
import com.swarnos.purchase.domain.Purchase;
import com.swarnos.repair.domain.RepairJob;
import com.swarnos.reports.service.PartyHistoryService;
import com.swarnos.sales.domain.CustomerExchange;
import com.swarnos.sales.domain.CustomerPurchase;
import com.swarnos.sales.domain.Sale;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import java.math.BigDecimal;
import java.util.List;

public record PartyHistoryResponse(@JsonUnwrapped Party party, BigDecimal balance, List<Sale> sales,
                                   List<CustomerPurchase> itemsBought, List<CustomerExchange> exchanges,
                                   List<Purchase> purchases, List<RepairJob> repairs, List<LedgerEntry> ledger) {

    public static PartyHistoryResponse of(PartyHistoryService.PartyHistory h) {
        boolean seesClass = CurrentUser.can(Permission.VIEW_PURCHASE_CLASS);
        return new PartyHistoryResponse(PartyResponse.mask(h.party()), h.balance(), h.sales(), h.itemsBought(), h.exchanges(),
                seesClass ? h.purchases() : h.purchases().stream().map(Purchase::withoutClass).toList(), h.repairs(), h.ledger());
    }
}
