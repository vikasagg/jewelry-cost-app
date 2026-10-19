package com.swarnos.purchase;

import static com.swarnos.common.Rows.str;
import static com.swarnos.common.Rows.strOrNull;

import com.swarnos.auth.CurrentUser;
import com.swarnos.auth.Permission;
import com.swarnos.common.ApiException;
import com.swarnos.common.AuditService;
import com.swarnos.common.BusinessClock;
import com.swarnos.common.Db;
import com.swarnos.common.DocNumbers;
import com.swarnos.common.Num;
import com.swarnos.common.Rows;
import com.swarnos.config.ConfigService;
import com.swarnos.items.ItemService;
import com.swarnos.ledger.LedgerService;
import com.swarnos.rates.RateService;
import com.swarnos.stock.StockLedger;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Purchases (BRD §8, §9): finished jewellery and gifting from vendors, old
 * metal from walk-in customers ("treat" purchase), paid in cash, by bank,
 * against gold, against silver, mixed, or on credit. Every purchase is
 * classified Seen (GST invoice, no cash) or Unseen, and both are fully booked.
 */
@Service
public class PurchaseService {
    private final Db db;
    private final ItemService items;
    private final RateService rates;
    private final LedgerService ledgers;
    private final StockLedger stock;
    private final DocNumbers numbers;
    private final ConfigService config;
    private final AuditService audit;
    private final BusinessClock clock;

    public PurchaseService(Db db, ItemService items, RateService rates, LedgerService ledgers, StockLedger stock,
                           DocNumbers numbers, ConfigService config, AuditService audit, BusinessClock clock) {
        this.db = db;
        this.items = items;
        this.rates = rates;
        this.ledgers = ledgers;
        this.stock = stock;
        this.numbers = numbers;
        this.config = config;
        this.audit = audit;
        this.clock = clock;
    }

    @SuppressWarnings("unchecked")
    @Transactional
    public Map<String, Object> create(Map<String, Object> b) {
        CurrentUser.require(Permission.PURCHASE);
        String kind = str(b.get("purchase_kind")).toUpperCase();
        if (!List.of("FINISHED", "OLD_METAL", "GIFTING").contains(kind)) {
            throw ApiException.bad("Purchase type must be FINISHED, OLD_METAL or GIFTING.");
        }
        Long partyId = Rows.idOrNull(b.get("party_id"));
        if (partyId == null) throw ApiException.bad("Choose the vendor or seller.");
        db.one("SELECT id FROM party WHERE id = ?", "Party not found", partyId);
        List<Map<String, Object>> lines = (List<Map<String, Object>>) b.getOrDefault("lines", List.of());
        if (lines.isEmpty()) throw ApiException.bad("Add at least one line.");

        Map<String, Object> pay = (Map<String, Object>) b.getOrDefault("payment", Map.of());
        BigDecimal cash = Num.of(pay.get("cash"));
        BigDecimal bank = Num.of(pay.get("bank"));
        BigDecimal goldFine = Num.of(pay.get("gold_fine"));
        BigDecimal silverFine = Num.of(pay.get("silver_fine"));
        String bankMode = str(pay.get("bank_mode")).isEmpty() ? "BANK" : str(pay.get("bank_mode")).toUpperCase();

        Optional<Map<String, Object>> rateSet = rates.approvedToday();
        boolean needsRate = kind.equals("OLD_METAL") || goldFine.signum() > 0 || silverFine.signum() > 0;
        if (needsRate && rateSet.isEmpty()) rates.requireApprovedToday();
        Long rateSetId = rateSet.map(Rows::id).orElse(null);

        String gstInvoice = strOrNull(b.get("gst_invoice_no"));
        String purchaseClass = gstInvoice != null && cash.signum() == 0 ? "SEEN" : "UNSEEN";
        String requested = strOrNull(b.get("purchase_class"));
        if (requested != null && !requested.equalsIgnoreCase(purchaseClass)) {
            CurrentUser.require(Permission.CHANGE_PURCHASE_CLASS);
            purchaseClass = requested.toUpperCase();
        }

        LocalDate today = clock.today();
        String no = numbers.next(config.get("purchase.prefix", "PUR"), today);
        long id = db.insert("""
                INSERT INTO purchase (purchase_no, business_date, party_id, purchase_kind, payment_mode, gst_invoice_no,
                                      purchase_class, rate_set_id, notes, created_by)
                VALUES (?,?,?,?, 'CREDIT', ?,?,?,?,?)""", no, today, partyId, kind, gstInvoice, purchaseClass,
                rateSetId, strOrNull(b.get("notes")), CurrentUser.usernameOrSystem());

        BigDecimal taxable = Num.ZERO;
        for (Map<String, Object> l : lines) {
            taxable = taxable.add(kind.equals("OLD_METAL") ? oldMetalLine(id, l, rateSetId, partyId) : itemLine(id, l, partyId, purchaseClass));
        }
        taxable = Num.r(taxable);
        BigDecimal gstPct = gstInvoice == null ? Num.ZERO : (b.get("gst_pct") == null ? Num.of(3) : Num.of(b.get("gst_pct")));
        BigDecimal gst = Num.pct(taxable, gstPct);
        BigDecimal total = Num.r(taxable.add(gst));

        BigDecimal goldValue = goldFine.signum() > 0 ? Num.mul(goldFine, rates.ratePerGram(rateSetId, "GOLD", "24K")) : Num.ZERO;
        BigDecimal silverValue = silverFine.signum() > 0 ? Num.mul(silverFine, rates.ratePerGram(rateSetId, "SILVER", "999")) : Num.ZERO;
        BigDecimal metalValue = Num.r(goldValue.add(silverValue));
        BigDecimal balance = Num.r(total.subtract(cash).subtract(bank).subtract(metalValue));
        if (balance.compareTo(new BigDecimal("-1")) < 0) {
            throw ApiException.bad("Payment (" + total.subtract(balance) + ") is more than the purchase value (" + total + ").");
        }

        String mode = paymentMode(cash, bank, goldFine, silverFine);
        db.update("""
                UPDATE purchase SET payment_mode = ?, taxable_amount = ?, gst_amount = ?, total_amount = ?, cash_paid = ?,
                    bank_paid = ?, bank_ref = ?, gold_fine_paid = ?, silver_fine_paid = ?, metal_value_paid = ?, balance_due = ?
                WHERE id = ?""", mode, taxable, gst, total, cash, bank, strOrNull(pay.get("bank_ref")), goldFine, silverFine,
                metalValue, balance, id);

        // Books: the party is owed the full value, then each payment leg reduces it.
        ledgers.post("PARTY", partyId, "PURCHASE", id, Num.ZERO, total, "Purchase " + no);
        ledgers.payment("PURCHASE", id, partyId, "OUT", "CASH", cash, null, "Purchase " + no);
        ledgers.payment("PURCHASE", id, partyId, "OUT", bankMode, bank, strOrNull(pay.get("bank_ref")), "Purchase " + no);
        if (goldFine.signum() > 0) {
            ledgers.post("GOLD", partyId, "PURCHASE", id, Num.ZERO, goldFine, "Fine gold given against " + no);
            ledgers.post("PARTY", partyId, "PURCHASE", id, goldValue, Num.ZERO, "Settled in fine gold " + goldFine + " g");
        }
        if (silverFine.signum() > 0) {
            ledgers.post("SILVER", partyId, "PURCHASE", id, Num.ZERO, silverFine, "Fine silver given against " + no);
            ledgers.post("PARTY", partyId, "PURCHASE", id, silverValue, Num.ZERO, "Settled in fine silver " + silverFine + " g");
        }
        audit.log("PURCHASE", "purchase", no, kind + " " + mode + " " + purchaseClass + " total " + total);

        Map<String, Object> out = get(id);
        List<String> warnings = new ArrayList<>();
        BigDecimal cashLimit = config.limit("cash.limit.purchase");
        if (cashLimit != null && cash.compareTo(cashLimit) > 0) {
            warnings.add("Cash paid " + cash + " is above the configured limit " + cashLimit + ".");
        }
        out.put("warnings", warnings);
        return out;
    }

    /** Finished jewellery or gifting: each line becomes a tagged item. Returns the line's purchase value. */
    private BigDecimal itemLine(long purchaseId, Map<String, Object> l, long partyId, String purchaseClass) {
        BigDecimal amount = Num.of(l.get("cost_amount"));
        if (amount.signum() <= 0) throw ApiException.bad("Enter the purchase value of every item.");
        long itemId = items.create(l, new ItemService.NewItemContext(partyId, purchaseId, purchaseClass, "PURCHASE",
                "PURCHASE", purchaseId));
        Map<String, Object> it = db.one("SELECT * FROM item WHERE id = ?", "Item not found", itemId);
        db.update("""
                INSERT INTO purchase_line (purchase_id, item_id, description, metal, purity_code, gross_wt, net_wt,
                                           fine_wt, quantity, amount)
                VALUES (?,?,?,?,?,?,?,?,?,?)""", purchaseId, itemId, it.get("tag_code") + " " + it.get("name"),
                it.get("metal"), it.get("purity_code"), it.get("gross_wt"), it.get("net_wt"), fine(it), it.get("quantity"), amount);
        return amount;
    }

    /** Old gold/silver bought by weight: valued at today's purity rate less deduction; fine metal enters the metal book. */
    private BigDecimal oldMetalLine(long purchaseId, Map<String, Object> l, Long rateSetId, long partyId) {
        String metal = str(l.get("metal")).toUpperCase();
        String purity = str(l.get("purity_code"));
        Map<String, Object> p = db.one("SELECT * FROM purity WHERE metal = ? AND code = ?", "Unknown purity " + metal + " " + purity,
                metal, purity);
        BigDecimal gross = Num.of(l.get("gross_wt"));
        BigDecimal net = l.get("net_wt") == null || str(l.get("net_wt")).isEmpty() ? gross : Num.of(l.get("net_wt"));
        if (!Num.positive(net) || net.compareTo(gross) > 0) throw ApiException.bad("Check the old metal weights.");
        BigDecimal deduction = l.get("deduction_pct") == null || str(l.get("deduction_pct")).isEmpty()
                ? config.decimal("oldmetal.deductionPct", Num.ZERO) : Num.of(l.get("deduction_pct"));
        BigDecimal rate = l.get("rate") == null || str(l.get("rate")).isEmpty()
                ? rates.ratePerGram(rateSetId, metal, purity) : Num.of(l.get("rate"));
        BigDecimal value = Num.r(Num.mul(net, rate).subtract(Num.pct(Num.mul(net, rate), deduction)));
        BigDecimal fineWt = Num.mul(net, (BigDecimal) p.get("fineness"));
        db.update("""
                INSERT INTO purchase_line (purchase_id, description, metal, purity_code, gross_wt, net_wt, fine_wt, rate,
                                           deduction_pct, amount)
                VALUES (?,?,?,?,?,?,?,?,?,?)""", purchaseId, str(l.get("description")).isEmpty() ? "Old " + metal.toLowerCase() : str(l.get("description")),
                metal, purity, gross, net, fineWt, rate, deduction, value);
        ledgers.post(metal, partyId, "PURCHASE", purchaseId, fineWt, Num.ZERO, "Old " + metal.toLowerCase() + " " + purity + " net " + net + " g");
        return value;
    }

    private BigDecimal fine(Map<String, Object> item) {
        if (item.get("metal") == null) return Num.ZERO;
        BigDecimal fineness = db.value("SELECT fineness FROM purity WHERE metal = ? AND code = ?", BigDecimal.class,
                item.get("metal"), item.get("purity_code"));
        return fineness == null ? Num.ZERO : Num.mul((BigDecimal) item.get("net_wt"), fineness);
    }

    static String paymentMode(BigDecimal cash, BigDecimal bank, BigDecimal gold, BigDecimal silver) {
        List<String> legs = new ArrayList<>();
        if (cash.signum() > 0) legs.add("CASH");
        if (bank.signum() > 0) legs.add("BANK");
        if (gold.signum() > 0) legs.add("GOLD");
        if (silver.signum() > 0) legs.add("SILVER");
        if (legs.isEmpty()) return "CREDIT";
        return legs.size() == 1 ? legs.get(0) : "MIXED";
    }

    public List<Map<String, Object>> list(String purchaseClass, String mode, LocalDate from, LocalDate to) {
        CurrentUser.require(Permission.PURCHASE);
        boolean canSeeClass = CurrentUser.can(Permission.VIEW_PURCHASE_CLASS);
        StringBuilder sql = new StringBuilder("""
                SELECT p.*, pa.name AS party_name, (SELECT COUNT(*) FROM purchase_line l WHERE l.purchase_id = p.id) AS line_count
                FROM purchase p LEFT JOIN party pa ON pa.id = p.party_id WHERE p.business_date BETWEEN ? AND ?""");
        List<Object> args = new ArrayList<>(List.of(from, to));
        if (canSeeClass && purchaseClass != null && !purchaseClass.equals("ALL")) {
            sql.append(" AND p.purchase_class = ?");
            args.add(purchaseClass);
        }
        if (mode != null && !mode.isBlank()) {
            sql.append(" AND p.payment_mode = ?");
            args.add(mode);
        }
        sql.append(" ORDER BY p.id DESC");
        List<Map<String, Object>> rows = db.rows(sql.toString(), args.toArray());
        if (!canSeeClass) rows.forEach(r -> r.remove("purchase_class"));
        return rows;
    }

    public Map<String, Object> get(long id) {
        CurrentUser.require(Permission.PURCHASE);
        Map<String, Object> p = new LinkedHashMap<>(db.one("""
                SELECT p.*, pa.name AS party_name, pa.phone AS party_phone FROM purchase p
                LEFT JOIN party pa ON pa.id = p.party_id WHERE p.id = ?""", "Purchase not found", id));
        p.put("lines", db.rows("""
                SELECT l.*, i.tag_code FROM purchase_line l LEFT JOIN item i ON i.id = l.item_id
                WHERE l.purchase_id = ? ORDER BY l.id""", id));
        if (!CurrentUser.can(Permission.VIEW_PURCHASE_CLASS)) p.remove("purchase_class");
        return p;
    }

    /** Corrects the Seen/Unseen class: owner only, with a reason, always logged (FR-SEE-01). */
    @Transactional
    public Map<String, Object> changeClass(long id, String newClass, String reason) {
        CurrentUser.require(Permission.CHANGE_PURCHASE_CLASS);
        String cls = str(newClass).toUpperCase();
        if (!List.of("SEEN", "UNSEEN").contains(cls)) throw ApiException.bad("Class must be SEEN or UNSEEN.");
        if (str(reason).isEmpty()) throw ApiException.bad("Give a reason for the change.");
        Map<String, Object> p = db.one("SELECT * FROM purchase WHERE id = ?", "Purchase not found", id);
        db.update("UPDATE purchase SET purchase_class = ? WHERE id = ?", cls, id);
        db.update("UPDATE item SET purchase_class = ? WHERE purchase_id = ?", cls, id);
        audit.log("PURCHASE_CLASS_CHANGE", "purchase", p.get("purchase_no"), p.get("purchase_class") + " -> " + cls + ": " + reason);
        return get(id);
    }

    /** Sends an unsold item back to its vendor (FR-PUR-05); the vendor's account is reduced by its cost. */
    @Transactional
    public Map<String, Object> returnToVendor(long itemId, String reason) {
        CurrentUser.require(Permission.PURCHASE);
        Map<String, Object> item = db.one("SELECT * FROM item WHERE id = ?", "Item not found", itemId);
        if (item.get("vendor_id") == null) throw ApiException.bad("This item has no vendor on record.");
        long vendor = Rows.id(item.get("vendor_id"));
        stock.post(new StockLedger.Move(itemId, "PURCHASE_RETURN", -Rows.integer(item.get("quantity"), 1), "IN_STOCK",
                "RETURNED", null, "PURCHASE_RETURN", itemId, reason));
        BigDecimal cost = Num.of(item.get("cost_amount"));
        ledgers.post("PARTY", vendor, "PURCHASE_RETURN", itemId, cost, Num.ZERO, "Returned " + item.get("tag_code"));
        audit.log("PURCHASE_RETURN", "item", item.get("tag_code"), reason);
        return items.get(itemId);
    }
}
