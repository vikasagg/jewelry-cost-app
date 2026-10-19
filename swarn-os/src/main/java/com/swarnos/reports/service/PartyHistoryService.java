package com.swarnos.reports.service;

import com.swarnos.accounting.domain.LedgerEntry;
import com.swarnos.accounting.service.LedgerService;
import com.swarnos.parties.domain.Party;
import com.swarnos.parties.service.PartyService;
import com.swarnos.purchase.domain.Purchase;
import com.swarnos.purchase.service.PurchaseService;
import com.swarnos.repair.domain.RepairJob;
import com.swarnos.repair.service.RepairService;
import com.swarnos.sales.domain.CustomerExchange;
import com.swarnos.sales.domain.CustomerPurchase;
import com.swarnos.sales.domain.Sale;
import com.swarnos.sales.service.SaleService;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.stereotype.Service;

/**
 * A party's complete, permanent history (FR-CUS-02): what they bought, returned,
 * exchanged, sold to us and had repaired, and their account.
 */
@Service
public class PartyHistoryService {
    private final PartyService parties;
    private final SaleService sales;
    private final PurchaseService purchases;
    private final RepairService repairs;
    private final LedgerService ledger;

    public PartyHistoryService(PartyService parties, SaleService sales, PurchaseService purchases, RepairService repairs,
                               LedgerService ledger) {
        this.parties = parties;
        this.sales = sales;
        this.purchases = purchases;
        this.repairs = repairs;
        this.ledger = ledger;
    }

    public record PartyHistory(Party party, BigDecimal balance, List<Sale> sales, List<CustomerPurchase> itemsBought,
                               List<CustomerExchange> exchanges, List<Purchase> purchases, List<RepairJob> repairs,
                               List<LedgerEntry> ledger) {}

    public PartyHistory history(long partyId) {
        Party party = parties.require(partyId);
        return new PartyHistory(party, ledger.partyBalance(partyId), sales.forCustomer(partyId), sales.itemsBoughtBy(partyId),
                sales.exchangesBy(partyId), purchases.forParty(partyId), repairs.forParty(partyId), ledger.partyEntries(partyId));
    }
}
