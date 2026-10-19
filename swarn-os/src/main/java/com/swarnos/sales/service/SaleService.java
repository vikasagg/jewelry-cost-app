package com.swarnos.sales.service;

import com.swarnos.accounting.domain.Book;
import com.swarnos.accounting.domain.Direction;
import com.swarnos.accounting.domain.DocumentType;
import com.swarnos.accounting.domain.Payment;
import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.accounting.service.LedgerService;
import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import com.swarnos.common.numbering.service.DocumentNumberService;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.inventory.domain.Item;
import com.swarnos.inventory.domain.ItemListing;
import com.swarnos.inventory.domain.ItemStatus;
import com.swarnos.inventory.domain.MovementType;
import com.swarnos.inventory.domain.PriceBreakdown;
import com.swarnos.inventory.domain.PriceInput;
import com.swarnos.inventory.domain.PricingEngine;
import com.swarnos.inventory.domain.StockMove;
import com.swarnos.inventory.service.ItemService;
import com.swarnos.inventory.service.StockLedgerService;
import com.swarnos.parties.domain.Party;
import com.swarnos.parties.service.PartyService;
import com.swarnos.rates.domain.DailyRates;
import com.swarnos.rates.domain.MetalValuation;
import com.swarnos.rates.domain.RateSetWithLines;
import com.swarnos.rates.service.RateService;
import com.swarnos.sales.domain.BillCalculator;
import com.swarnos.sales.domain.BillQuote;
import com.swarnos.sales.domain.CustomerExchange;
import com.swarnos.sales.domain.CustomerPurchase;
import com.swarnos.sales.domain.ExchangeLine;
import com.swarnos.sales.domain.QuotedExchange;
import com.swarnos.sales.domain.QuotedLine;
import com.swarnos.sales.domain.RoundOff;
import com.swarnos.sales.domain.Sale;
import com.swarnos.sales.domain.SaleLine;
import com.swarnos.sales.domain.SaleStatus;
import com.swarnos.sales.domain.SaleView;
import com.swarnos.sales.domain.SalesDayStats;
import com.swarnos.sales.repository.SaleRepository;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.settings.domain.Purity;
import com.swarnos.settings.domain.SettingKeys;
import com.swarnos.settings.domain.ShopProfile;
import com.swarnos.settings.service.MasterDataService;
import com.swarnos.settings.service.SettingsService;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Sales billing (BRD §7): price scanned items from today's approved rate, take
 * old gold/silver in exchange, accept split payments, and post stock and books
 * in one transaction.
 */
@Service
public class SaleService {
    private final SaleRepository sales;
    private final ItemService items;
    private final StockLedgerService stockLedger;
    private final RateService rates;
    private final LedgerService ledger;
    private final PartyService parties;
    private final MasterDataService masters;
    private final SettingsService settings;
    private final DocumentNumberService numbers;
    private final AuditService audit;
    private final BusinessClock clock;

    public SaleService(SaleRepository sales, ItemService items, StockLedgerService stockLedger, RateService rates,
                       LedgerService ledger, PartyService parties, MasterDataService masters, SettingsService settings,
                       DocumentNumberService numbers, AuditService audit, BusinessClock clock) {
        this.sales = sales;
        this.items = items;
        this.stockLedger = stockLedger;
        this.rates = rates;
        this.ledger = ledger;
        this.parties = parties;
        this.masters = masters;
        this.settings = settings;
        this.numbers = numbers;
        this.audit = audit;
        this.clock = clock;
    }

    public record SaleDetail(SaleView view, List<SaleLine> lines, List<ExchangeLine> exchange, List<Payment> payments,
                             RateSetWithLines rateSet, ShopProfile shop) {}

    public record SaleResult(SaleDetail detail, List<String> warnings) {}

    // ---------- pricing ----------

    /** The full calculation of a bill; saves nothing. */
    public BillQuote quote(SaleCommand cmd) {
        DailyRates today = rates.requireTodayRates();
        if (cmd.lines().isEmpty()) throw BusinessException.validation("Scan or add at least one item.");
        List<QuotedLine> lines = new ArrayList<>();
        Set<Long> seen = new HashSet<>();
        for (SaleCommand.Line l : cmd.lines()) {
            ItemListing listing = l.itemId() != null ? items.listing(l.itemId()) : items.requireByCode(l.tagCode()).item().listing();
            Item item = listing.item();
            if (!seen.add(item.id())) throw BusinessException.validation("Tag " + item.tagCode() + " is on the bill twice.");
            if (item.status() != ItemStatus.IN_STOCK) {
                throw BusinessException.conflict("Tag " + item.tagCode() + " is " + item.status().name().toLowerCase().replace('_', ' ') + ".");
            }
            BigDecimal rate = item.metal() == null ? Decimals.ZERO : today.ratePerGram(item.metal(), item.purityCode());
            PriceBreakdown p = PricingEngine.price(PriceInput.of(listing, rate), l.discount());
            lines.add(new QuotedLine(item.id(), item.tagCode(), item.name() + (item.purityCode() == null ? "" : " " + item.purityCode()),
                    item.metal(), item.purityCode(), item.quantity(), item.grossWt(), item.netWt(), item.huid(), p.rate(),
                    p.metalValue(), p.wastageValue(), p.makingValue(), p.stoneValue(), p.discount(), p.taxable(), p.gstPct(),
                    p.gst(), p.total()));
        }
        List<QuotedExchange> exchange = new ArrayList<>();
        for (SaleCommand.Exchange x : cmd.exchange()) exchange.add(valueExchange(x, today));
        return BillCalculator.total(today.rateSetId(), lines, exchange,
                RoundOff.fromSetting(settings.text(SettingKeys.BILL_ROUND_OFF, "NONE")));
    }

    private QuotedExchange valueExchange(SaleCommand.Exchange x, DailyRates today) {
        if (x.metal() == null) throw BusinessException.validation("Choose the metal of the exchange line.");
        Purity purity = masters.purity(x.metal(), x.purityCode());
        BigDecimal gross = Decimals.orZero(x.grossWt());
        BigDecimal net = x.netWt() == null ? gross : Decimals.round(x.netWt());
        if (!Decimals.isPositive(net) || net.compareTo(gross) > 0) throw BusinessException.validation("Check the exchange weights.");
        BigDecimal deduction = x.deductionPct() != null ? Decimals.round(x.deductionPct())
                : settings.decimal(SettingKeys.EXCHANGE_DEDUCTION_PCT, Decimals.ZERO);
        BigDecimal rate = today.ratePerGram(x.metal(), purity.code());
        MetalValuation v = MetalValuation.of(net, rate, deduction, purity.fineness());
        String description = x.description() == null || x.description().isBlank()
                ? "Old " + x.metal().name().toLowerCase() + " " + purity.code() : x.description().trim();
        return new QuotedExchange(description, x.metal(), purity.code(), gross, net, v.fineWeight(), rate, deduction, v.value());
    }

    // ---------- commands ----------

    @Transactional
    public SaleResult create(SaleCommand cmd) {
        CurrentUser.require(Permission.BILL);
        BillQuote q = quote(cmd);
        Party customer = cmd.customerId() == null ? null : parties.require(cmd.customerId());

        BigDecimal maxDiscountPct = settings.decimal(SettingKeys.DISCOUNT_MAX_PCT_SALES, Decimals.ZERO);
        if (BillCalculator.discountNeedsApproval(q, maxDiscountPct) && !CurrentUser.can(Permission.DISCOUNT_OVERRIDE)) {
            throw BusinessException.forbidden("Discount above " + maxDiscountPct + "% needs a manager.");
        }
        BigDecimal paid = Decimals.ZERO, cashIn = Decimals.ZERO;
        for (SaleCommand.PaymentLeg p : cmd.payments()) {
            BigDecimal amt = Decimals.orZero(p.amount());
            if (amt.signum() < 0) throw BusinessException.validation("Payment amounts cannot be negative.");
            paid = paid.add(amt);
            if (p.mode() == PaymentMode.CASH) cashIn = cashIn.add(amt);
        }
        BigDecimal balance = Decimals.round(q.netPayable().subtract(paid));
        if (balance.signum() < 0) throw BusinessException.validation("Payments are more than the bill amount by " + balance.negate() + ".");
        if (balance.signum() > 0 && customer == null) throw BusinessException.validation("Choose a customer for a bill with an amount due.");

        LocalDate today = clock.today();
        String invoiceNo = numbers.next(settings.text(SettingKeys.INVOICE_PREFIX, "INV"), today);
        Long customerId = customer == null ? null : customer.id();
        long saleId = sales.insert(invoiceNo, today, customerId, q, Decimals.round(paid), balance, cmd.notes(),
                CurrentUser.usernameOrSystem());
        for (QuotedLine l : q.lines()) {
            sales.insertLine(saleId, l);
            stockLedger.post(new StockMove(l.itemId(), MovementType.SALE, -l.quantity(), Set.of(ItemStatus.IN_STOCK), ItemStatus.SOLD,
                    null, "SALE", saleId, invoiceNo));
        }
        for (QuotedExchange x : q.exchange()) {
            sales.insertExchange(saleId, x);
            ledger.post(Book.forMetal(x.metal()), customerId, DocumentType.SALE, saleId, x.fineWt(), null,
                    "Exchange on " + invoiceNo + ": " + x.description());
        }
        if (customerId != null) ledger.post(Book.PARTY, customerId, DocumentType.SALE, saleId, q.netPayable(), null, "Bill " + invoiceNo);
        for (SaleCommand.PaymentLeg p : cmd.payments()) {
            ledger.recordPayment(DocumentType.SALE, saleId, customerId, Direction.IN, p.mode(), p.amount(), p.reference(), "Bill " + invoiceNo);
        }
        audit.record("SALE", "sale", invoiceNo, q.lines().size() + " items, net " + q.netPayable());
        return new SaleResult(detail(saleId), warnings(q, customer, cashIn));
    }

    /** Full return: items back to stock, the customer refunded what they paid plus the exchange value. */
    @Transactional
    public SaleDetail returnSale(long id, String reason, PaymentMode refundMode) {
        CurrentUser.require(Permission.SALE_RETURN);
        Sale s = view(id).sale();
        if (s.status() != SaleStatus.FINAL) throw BusinessException.conflict("This bill is already returned.");
        if (reason == null || reason.isBlank()) throw BusinessException.validation("Give a reason for the return.");
        for (SaleLine l : sales.findLines(id)) {
            stockLedger.post(new StockMove(l.itemId(), MovementType.SALE_RETURN, l.quantity(), Set.of(ItemStatus.SOLD),
                    ItemStatus.IN_STOCK, null, "SALE_RETURN", id, reason));
        }
        String label = "Return of " + s.invoiceNo();
        if (s.customerId() != null) ledger.post(Book.PARTY, s.customerId(), DocumentType.RETURN, id, null, s.netPayable(), label);
        ledger.recordPayment(DocumentType.RETURN, id, s.customerId(), Direction.OUT, refundMode == null ? PaymentMode.CASH : refundMode,
                s.paidTotal().add(s.exchangeTotal()), null, "Refund for " + s.invoiceNo());
        if (s.customerId() != null && s.exchangeTotal().signum() > 0) {
            ledger.post(Book.PARTY, s.customerId(), DocumentType.RETURN, id, null, s.exchangeTotal(), "Exchange value on returned " + s.invoiceNo());
        }
        sales.markReturned(id, (s.notes() == null ? "" : s.notes() + " | ") + "Returned: " + reason);
        audit.record("SALE_RETURN", "sale", s.invoiceNo(), reason);
        return detail(id);
    }

    // ---------- queries ----------

    public SaleDetail detail(long id) {
        SaleView v = view(id);
        return new SaleDetail(v, sales.findLines(id), sales.findExchange(id),
                ledger.paymentsFor(id, DocumentType.SALE, DocumentType.RETURN), rates.get(v.sale().rateSetId()), settings.shopProfile());
    }

    public List<SaleView> list(LocalDate from, LocalDate to, String text) {
        return sales.list(from, to, text);
    }

    public List<SaleView> recent(int limit) {
        return sales.recent(limit);
    }

    public SalesDayStats statsToday() {
        return sales.statsOn(clock.today());
    }

    public List<Sale> forCustomer(long customerId) {
        return sales.findByCustomer(customerId);
    }

    public List<CustomerPurchase> itemsBoughtBy(long customerId) {
        return sales.itemsBoughtBy(customerId);
    }

    public List<CustomerExchange> exchangesBy(long customerId) {
        return sales.exchangesBy(customerId);
    }

    private SaleView view(long id) {
        return sales.findView(id).orElseThrow(() -> BusinessException.notFound("Bill not found"));
    }

    private List<String> warnings(BillQuote q, Party customer, BigDecimal cashIn) {
        List<String> warnings = new ArrayList<>();
        settings.limit(SettingKeys.CASH_LIMIT_SALE).filter(limit -> cashIn.compareTo(limit) > 0)
                .ifPresent(limit -> warnings.add("Cash received " + cashIn + " is above the configured limit " + limit + "."));
        settings.limit(SettingKeys.KYC_PAN_THRESHOLD)
                .filter(limit -> q.netPayable().compareTo(limit) >= 0 && (customer == null || !customer.hasPan()))
                .ifPresent(limit -> warnings.add("Bill is above the PAN threshold " + limit + " but the customer has no PAN on record."));
        return warnings;
    }
}
