package com.swarnos.purchase.service;

import com.swarnos.accounting.domain.Book;
import com.swarnos.accounting.domain.Direction;
import com.swarnos.accounting.domain.DocumentType;
import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.accounting.service.LedgerService;
import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import com.swarnos.common.numbering.service.DocumentNumberService;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.inventory.domain.Item;
import com.swarnos.inventory.domain.ItemOrigin;
import com.swarnos.inventory.domain.ItemStatus;
import com.swarnos.inventory.domain.MovementType;
import com.swarnos.inventory.domain.NewItem;
import com.swarnos.inventory.domain.PurchaseClass;
import com.swarnos.inventory.domain.StockMove;
import com.swarnos.inventory.service.ItemService;
import com.swarnos.inventory.service.StockLedgerService;
import com.swarnos.parties.domain.Party;
import com.swarnos.parties.service.PartyService;
import com.swarnos.purchase.domain.OldMetalLine;
import com.swarnos.purchase.domain.PaymentLegs;
import com.swarnos.purchase.domain.DayTotals;
import com.swarnos.purchase.domain.Purchase;
import com.swarnos.purchase.domain.PurchaseView;
import com.swarnos.purchase.domain.PurchaseKind;
import com.swarnos.purchase.domain.PurchaseLine;
import com.swarnos.purchase.domain.PurchaseTotals;
import com.swarnos.purchase.domain.SettlementMode;
import com.swarnos.purchase.repository.PurchaseRepository;
import com.swarnos.rates.domain.DailyRates;
import com.swarnos.rates.domain.MetalValuation;
import com.swarnos.rates.service.RateService;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.Purity;
import com.swarnos.settings.domain.SettingKeys;
import com.swarnos.settings.service.MasterDataService;
import com.swarnos.settings.service.SettingsService;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Purchases (BRD §8, §9): finished jewellery and gifting become tagged items;
 * old metal goes to the metal book in fine weight. Paid in cash, by bank, in fine
 * gold or silver, mixed, or on credit; every purchase is classified Seen/Unseen
 * and fully booked either way.
 */
@Service
public class PurchaseService {
    private static final BigDecimal DEFAULT_GST_PCT = new BigDecimal("3");

    private final PurchaseRepository purchases;
    private final ItemService items;
    private final StockLedgerService stockLedger;
    private final PartyService parties;
    private final RateService rates;
    private final LedgerService ledger;
    private final MasterDataService masters;
    private final SettingsService settings;
    private final DocumentNumberService numbers;
    private final AuditService audit;
    private final BusinessClock clock;

    public PurchaseService(PurchaseRepository purchases, ItemService items, StockLedgerService stockLedger, PartyService parties,
                           RateService rates, LedgerService ledger, MasterDataService masters, SettingsService settings,
                           DocumentNumberService numbers, AuditService audit, BusinessClock clock) {
        this.purchases = purchases;
        this.items = items;
        this.stockLedger = stockLedger;
        this.parties = parties;
        this.rates = rates;
        this.ledger = ledger;
        this.masters = masters;
        this.settings = settings;
        this.numbers = numbers;
        this.audit = audit;
        this.clock = clock;
    }

    public record PurchaseDetail(PurchaseView view, List<PurchaseLine> lines) {}

    public record PurchaseResult(PurchaseDetail detail, List<String> warnings) {}

    // ---------- commands ----------

    @Transactional
    public PurchaseResult create(PurchaseCommand cmd) {
        CurrentUser.require(Permission.PURCHASE);
        if (cmd.kind() == null) throw BusinessException.validation("Purchase type must be FINISHED, OLD_METAL or GIFTING.");
        if (cmd.partyId() == null) throw BusinessException.validation("Choose the vendor or seller.");
        Party party = parties.require(cmd.partyId());
        int lineCount = cmd.kind().createsItems() ? size(cmd.items()) : size(cmd.oldMetal());
        if (lineCount == 0) throw BusinessException.validation("Add at least one line.");
        PaymentLegs legs = cmd.payment() == null ? PaymentLegs.none() : cmd.payment();

        boolean needsRate = cmd.kind() == PurchaseKind.OLD_METAL || legs.settlesInMetal();
        Optional<DailyRates> todayRates = needsRate ? Optional.of(rates.requireTodayRates()) : rates.todayRatesIfApproved();

        String gstInvoice = cmd.gstInvoiceNo() == null || cmd.gstInvoiceNo().isBlank() ? null : cmd.gstInvoiceNo().trim();
        PurchaseClass cls = PurchaseClass.classify(gstInvoice != null, legs.anyCash());
        if (cmd.requestedClass() != null && cmd.requestedClass() != cls) {
            CurrentUser.require(Permission.CHANGE_PURCHASE_CLASS);
            cls = cmd.requestedClass();
        }

        LocalDate today = clock.today();
        String no = numbers.next(settings.text(SettingKeys.PURCHASE_PREFIX, "PUR"), today);
        long id = purchases.insertHeader(no, today, party.id(), cmd.kind(), gstInvoice, cls,
                todayRates.map(DailyRates::rateSetId).orElse(null), cmd.notes(), CurrentUser.usernameOrSystem());

        BigDecimal taxable = Decimals.ZERO;
        if (cmd.kind().createsItems()) {
            for (NewItem line : cmd.items()) taxable = taxable.add(addItemLine(id, party.id(), cls, line));
        } else {
            for (OldMetalLine line : cmd.oldMetal()) taxable = taxable.add(addOldMetalLine(id, party.id(), line, todayRates.orElseThrow()));
        }

        BigDecimal gstPct = gstInvoice == null ? Decimals.ZERO : (cmd.gstPct() == null ? DEFAULT_GST_PCT : cmd.gstPct());
        BigDecimal goldValue = legs.goldFine().signum() > 0
                ? Decimals.multiply(legs.goldFine(), todayRates.orElseThrow().ratePerGram(Metal.GOLD, "24K")) : Decimals.ZERO;
        BigDecimal silverValue = legs.silverFine().signum() > 0
                ? Decimals.multiply(legs.silverFine(), todayRates.orElseThrow().ratePerGram(Metal.SILVER, "999")) : Decimals.ZERO;
        PurchaseTotals totals = PurchaseTotals.of(taxable, gstPct, legs, goldValue.add(silverValue));
        purchases.updateSettlement(id, legs.mode(), totals, legs);

        postToBooks(id, no, party.id(), totals, legs, goldValue, silverValue);
        audit.record("PURCHASE", "purchase", no, cmd.kind() + " " + legs.mode() + " " + cls + " total " + totals.total());

        List<String> warnings = new ArrayList<>();
        settings.limit(SettingKeys.CASH_LIMIT_PURCHASE).filter(limit -> legs.cash().compareTo(limit) > 0)
                .ifPresent(limit -> warnings.add("Cash paid " + legs.cash() + " is above the configured limit " + limit + "."));
        return new PurchaseResult(detail(id), warnings);
    }

    /** Owner corrects the Seen/Unseen class with a logged reason (FR-SEE-01). */
    @Transactional
    public PurchaseDetail changeClass(long id, PurchaseClass cls, String reason) {
        CurrentUser.require(Permission.CHANGE_PURCHASE_CLASS);
        if (cls == null) throw BusinessException.validation("Class must be SEEN or UNSEEN.");
        if (reason == null || reason.isBlank()) throw BusinessException.validation("Give a reason for the change.");
        Purchase p = view(id).purchase();
        purchases.updateClass(id, cls);
        items.changePurchaseClass(id, cls);
        audit.record("PURCHASE_CLASS_CHANGE", "purchase", p.purchaseNo(), p.purchaseClass() + " -> " + cls + ": " + reason);
        return detail(id);
    }

    /** Sends an unsold item back to its vendor (FR-PUR-05); the vendor's account is reduced by its cost. */
    @Transactional
    public long returnToVendor(long itemId, String reason) {
        CurrentUser.require(Permission.PURCHASE);
        Item item = items.listing(itemId).item();
        if (item.vendorId() == null) throw BusinessException.validation("This item has no vendor on record.");
        stockLedger.post(new StockMove(itemId, MovementType.PURCHASE_RETURN, -item.quantity(), Set.of(ItemStatus.IN_STOCK),
                ItemStatus.RETURNED, null, "PURCHASE_RETURN", itemId, reason));
        ledger.post(Book.PARTY, item.vendorId(), DocumentType.PURCHASE_RETURN, itemId, item.costAmount(), null,
                "Returned " + item.tagCode());
        audit.record("PURCHASE_RETURN", "item", item.tagCode(), reason);
        return itemId;
    }

    // ---------- queries ----------

    public PurchaseDetail detail(long id) {
        CurrentUser.require(Permission.PURCHASE);
        return new PurchaseDetail(view(id), purchases.findLines(id));
    }

    public List<PurchaseView> list(PurchaseClass cls, SettlementMode mode, LocalDate from, LocalDate to) {
        CurrentUser.require(Permission.PURCHASE);
        return purchases.list(CurrentUser.can(Permission.VIEW_PURCHASE_CLASS) ? cls : null, mode, from, to);
    }

    public List<Purchase> forParty(long partyId) {
        return purchases.findByParty(partyId);
    }

    public DayTotals totalsToday() {
        return purchases.totalsOn(clock.today());
    }

    // ---------- helpers ----------

    private BigDecimal addItemLine(long purchaseId, long partyId, PurchaseClass cls, NewItem line) {
        if (!Decimals.isPositive(line.costAmount())) throw BusinessException.validation("Enter the purchase value of every item.");
        long itemId = items.create(line, ItemOrigin.purchase(purchaseId, partyId, cls));
        Item item = items.listing(itemId).item();
        BigDecimal fine = item.metal() == null ? Decimals.ZERO
                : Decimals.multiply(item.netWt(), masters.purity(item.metal(), item.purityCode()).fineness());
        BigDecimal amount = Decimals.round(line.costAmount());
        purchases.insertLine(new PurchaseLine(0, purchaseId, itemId, item.tagCode() + " " + item.name(), item.metal(),
                item.purityCode(), item.grossWt(), item.netWt(), fine, Decimals.ZERO, Decimals.ZERO, item.quantity(), amount, null));
        return amount;
    }

    private BigDecimal addOldMetalLine(long purchaseId, long partyId, OldMetalLine line, DailyRates todayRates) {
        if (line.metal() == null) throw BusinessException.validation("Choose the metal of the old metal line.");
        Purity purity = masters.purity(line.metal(), line.purityCode());
        BigDecimal gross = Decimals.orZero(line.grossWt());
        BigDecimal net = line.netWt() == null ? gross : Decimals.round(line.netWt());
        if (!Decimals.isPositive(net) || net.compareTo(gross) > 0) throw BusinessException.validation("Check the old metal weights.");
        BigDecimal deduction = line.deductionPct() != null ? line.deductionPct()
                : settings.decimal(SettingKeys.OLD_METAL_DEDUCTION_PCT, Decimals.ZERO);
        BigDecimal rate = line.rate() != null ? Decimals.round(line.rate()) : todayRates.ratePerGram(line.metal(), purity.code());
        MetalValuation v = MetalValuation.of(net, rate, deduction, purity.fineness());
        String description = line.description() == null || line.description().isBlank()
                ? "Old " + line.metal().name().toLowerCase() : line.description().trim();
        purchases.insertLine(new PurchaseLine(0, purchaseId, null, description, line.metal(), purity.code(), gross, net,
                v.fineWeight(), rate, Decimals.round(deduction), 1, v.value(), null));
        ledger.post(Book.forMetal(line.metal()), partyId, DocumentType.PURCHASE, purchaseId, v.fineWeight(), null,
                "Old " + line.metal().name().toLowerCase() + " " + purity.code() + " net " + net + " g");
        return v.value();
    }

    /** The party is owed the full value, then each payment leg reduces it. */
    private void postToBooks(long id, String no, long partyId, PurchaseTotals totals, PaymentLegs legs, BigDecimal goldValue,
                             BigDecimal silverValue) {
        String narration = "Purchase " + no;
        ledger.post(Book.PARTY, partyId, DocumentType.PURCHASE, id, null, totals.total(), narration);
        ledger.recordPayment(DocumentType.PURCHASE, id, partyId, Direction.OUT, PaymentMode.CASH, legs.cash(), null, narration);
        ledger.recordPayment(DocumentType.PURCHASE, id, partyId, Direction.OUT, legs.bankMode(), legs.bank(), legs.bankRef(), narration);
        if (legs.goldFine().signum() > 0) {
            ledger.post(Book.GOLD, partyId, DocumentType.PURCHASE, id, null, legs.goldFine(), "Fine gold given against " + no);
            ledger.post(Book.PARTY, partyId, DocumentType.PURCHASE, id, goldValue, null, "Settled in fine gold " + legs.goldFine() + " g");
        }
        if (legs.silverFine().signum() > 0) {
            ledger.post(Book.SILVER, partyId, DocumentType.PURCHASE, id, null, legs.silverFine(), "Fine silver given against " + no);
            ledger.post(Book.PARTY, partyId, DocumentType.PURCHASE, id, silverValue, null, "Settled in fine silver " + legs.silverFine() + " g");
        }
    }

    private PurchaseView view(long id) {
        return purchases.findView(id).orElseThrow(() -> BusinessException.notFound("Purchase not found"));
    }

    private static int size(List<?> l) {
        return l == null ? 0 : l.size();
    }
}
