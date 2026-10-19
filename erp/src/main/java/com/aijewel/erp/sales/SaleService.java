package com.aijewel.erp.sales;

import static com.aijewel.erp.common.Rows.str;
import static com.aijewel.erp.common.Rows.strOrNull;

import com.aijewel.erp.auth.CurrentUser;
import com.aijewel.erp.auth.Permission;
import com.aijewel.erp.common.ApiException;
import com.aijewel.erp.common.AuditService;
import com.aijewel.erp.common.BusinessClock;
import com.aijewel.erp.common.Db;
import com.aijewel.erp.common.DocNumbers;
import com.aijewel.erp.common.Num;
import com.aijewel.erp.common.Rows;
import com.aijewel.erp.config.ConfigService;
import com.aijewel.erp.items.ItemService;
import com.aijewel.erp.items.PriceBreakdown;
import com.aijewel.erp.items.PricingEngine;
import com.aijewel.erp.ledger.LedgerService;
import com.aijewel.erp.rates.RateService;
import com.aijewel.erp.stock.StockLedger;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Sales billing (BRD §7): scan tags, price from today's approved rate, take
 * old gold/silver in exchange, accept split payments, post stock and books in
 * one transaction.
 */
@Service
public class SaleService {
    private final Db db;
    private final ItemService items;
    private final RateService rates;
    private final StockLedger stock;
    private final LedgerService ledgers;
    private final DocNumbers numbers;
    private final ConfigService config;
    private final AuditService audit;
    private final BusinessClock clock;

    public SaleService(Db db, ItemService items, RateService rates, StockLedger stock, LedgerService ledgers,
                       DocNumbers numbers, ConfigService config, AuditService audit, BusinessClock clock) {
        this.db = db;
        this.items = items;
        this.rates = rates;
        this.stock = stock;
        this.ledgers = ledgers;
        this.numbers = numbers;
        this.config = config;
        this.audit = audit;
        this.clock = clock;
    }

    /** The full calculation of a bill, used both for the live preview and for saving. */
    record Quote(Map<String, Object> rateSet, List<Map<String, Object>> lines, List<Map<String, Object>> exchange,
                 BigDecimal itemsTotal, BigDecimal discount, BigDecimal taxable, BigDecimal gst, BigDecimal exchangeTotal,
                 BigDecimal roundOff, BigDecimal netPayable, BigDecimal grossBeforeDiscount) {

        Map<String, Object> toMap() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("rate_set_id", rateSet.get("id"));
            m.put("lines", lines);
            m.put("exchange", exchange);
            m.put("items_total", itemsTotal);
            m.put("discount", discount);
            m.put("taxable_total", taxable);
            m.put("gst_total", gst);
            m.put("exchange_total", exchangeTotal);
            m.put("round_off", roundOff);
            m.put("net_payable", netPayable);
            return m;
        }
    }

    @SuppressWarnings("unchecked")
    Quote quote(Map<String, Object> b) {
        Map<String, Object> rateSet = rates.requireApprovedToday();
        long rateSetId = Rows.id(rateSet);
        List<Map<String, Object>> reqLines = (List<Map<String, Object>>) b.getOrDefault("lines", List.of());
        if (reqLines.isEmpty()) throw ApiException.bad("Scan or add at least one item.");

        List<Map<String, Object>> lines = new ArrayList<>();
        Set<Long> seen = new HashSet<>();
        BigDecimal itemsTotal = Num.ZERO, discount = Num.ZERO, taxable = Num.ZERO, gst = Num.ZERO, gross = Num.ZERO;
        for (Map<String, Object> l : reqLines) {
            Map<String, Object> item = l.get("item_id") != null ? items.get(Rows.id(l.get("item_id"))) : items.byCode(str(l.get("tag_code")));
            long itemId = Rows.id(item);
            if (!seen.add(itemId)) throw ApiException.bad("Tag " + item.get("tag_code") + " is on the bill twice.");
            if (!"IN_STOCK".equals(item.get("status"))) {
                throw ApiException.conflict("Tag " + item.get("tag_code") + " is " + str(item.get("status")).toLowerCase().replace('_', ' ') + ".");
            }
            BigDecimal rate = item.get("metal") == null ? Num.ZERO
                    : rates.ratePerGram(rateSetId, (String) item.get("metal"), (String) item.get("purity_code"));
            PriceBreakdown p = PricingEngine.price(items.priceInput(item, rate), Num.of(l.get("discount")));
            Map<String, Object> line = new LinkedHashMap<>();
            line.put("item_id", itemId);
            line.put("tag_code", item.get("tag_code"));
            line.put("description", item.get("name") + (item.get("purity_code") == null ? "" : " " + item.get("purity_code")));
            line.put("metal", item.get("metal"));
            line.put("purity_code", item.get("purity_code"));
            line.put("quantity", item.get("quantity"));
            line.put("gross_wt", item.get("gross_wt"));
            line.put("net_wt", item.get("net_wt"));
            line.put("huid", item.get("huid"));
            line.put("rate", p.rate());
            line.put("metal_value", p.metalValue());
            line.put("wastage_value", p.wastageValue());
            line.put("making_value", p.makingValue());
            line.put("stone_value", p.stoneValue());
            line.put("discount", p.discount());
            line.put("taxable", p.taxable());
            line.put("gst_pct", p.gstPct());
            line.put("gst", p.gst());
            line.put("line_total", p.total());
            lines.add(line);
            itemsTotal = itemsTotal.add(p.total());
            discount = discount.add(p.discount());
            taxable = taxable.add(p.taxable());
            gst = gst.add(p.gst());
            gross = gross.add(p.taxable()).add(p.discount());
        }

        List<Map<String, Object>> exchange = new ArrayList<>();
        BigDecimal exchangeTotal = Num.ZERO;
        for (Map<String, Object> x : (List<Map<String, Object>>) b.getOrDefault("exchange", List.of())) {
            String metal = str(x.get("metal")).toUpperCase();
            String purity = str(x.get("purity_code"));
            Map<String, Object> p = db.one("SELECT * FROM purity WHERE metal = ? AND code = ?", "Unknown purity " + metal + " " + purity,
                    metal, purity);
            BigDecimal grossWt = Num.of(x.get("gross_wt"));
            BigDecimal net = x.get("net_wt") == null || str(x.get("net_wt")).isEmpty() ? grossWt : Num.of(x.get("net_wt"));
            if (!Num.positive(net) || net.compareTo(grossWt) > 0) throw ApiException.bad("Check the exchange weights.");
            BigDecimal deduction = x.get("deduction_pct") == null || str(x.get("deduction_pct")).isEmpty()
                    ? config.decimal("exchange.deductionPct", Num.ZERO) : Num.of(x.get("deduction_pct"));
            BigDecimal rate = rates.ratePerGram(rateSetId, metal, purity);
            BigDecimal before = Num.mul(net, rate);
            BigDecimal value = Num.r(before.subtract(Num.pct(before, deduction)));
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("description", str(x.get("description")).isEmpty() ? "Old " + metal.toLowerCase() + " " + purity : str(x.get("description")));
            row.put("metal", metal);
            row.put("purity_code", purity);
            row.put("gross_wt", grossWt);
            row.put("net_wt", net);
            row.put("fine_wt", Num.mul(net, (BigDecimal) p.get("fineness")));
            row.put("rate", rate);
            row.put("deduction_pct", deduction);
            row.put("value", value);
            exchange.add(row);
            exchangeTotal = exchangeTotal.add(value);
        }

        BigDecimal beforeRound = Num.r(itemsTotal.subtract(exchangeTotal));
        BigDecimal net = "RUPEE".equals(config.get("bill.roundOff", "NONE"))
                ? Num.r(beforeRound.setScale(0, RoundingMode.HALF_UP)) : beforeRound;
        if (net.signum() < 0) {
            throw ApiException.bad("The exchange is worth more than the items. Record the extra as an old-metal purchase.");
        }
        return new Quote(rateSet, lines, exchange, Num.r(itemsTotal), Num.r(discount), Num.r(taxable), Num.r(gst),
                Num.r(exchangeTotal), Num.r(net.subtract(beforeRound)), net, Num.r(gross));
    }

    public Map<String, Object> preview(Map<String, Object> b) {
        return quote(b).toMap();
    }

    @SuppressWarnings("unchecked")
    @Transactional
    public Map<String, Object> create(Map<String, Object> b) {
        CurrentUser.require(Permission.BILL);
        Quote q = quote(b);
        Long customerId = Rows.idOrNull(b.get("customer_id"));
        Map<String, Object> customer = customerId == null ? null
                : db.one("SELECT * FROM party WHERE id = ?", "Customer not found", customerId);

        BigDecimal maxPct = config.decimal("discount.maxPctSales", Num.ZERO);
        if (q.discount().signum() > 0 && q.grossBeforeDiscount().signum() > 0
                && Num.pct(q.grossBeforeDiscount(), maxPct).compareTo(q.discount()) < 0) {
            if (!CurrentUser.can(Permission.DISCOUNT_OVERRIDE)) {
                throw ApiException.forbidden("Discount above " + maxPct + "% needs a manager.");
            }
        }

        List<Map<String, Object>> payments = (List<Map<String, Object>>) b.getOrDefault("payments", List.of());
        BigDecimal paid = Num.ZERO, cashIn = Num.ZERO;
        for (Map<String, Object> p : payments) {
            BigDecimal amt = Num.of(p.get("amount"));
            if (amt.signum() < 0) throw ApiException.bad("Payment amounts cannot be negative.");
            paid = paid.add(amt);
            if ("CASH".equalsIgnoreCase(str(p.get("mode")))) cashIn = cashIn.add(amt);
        }
        BigDecimal balance = Num.r(q.netPayable().subtract(paid));
        if (balance.signum() < 0) throw ApiException.bad("Payments are more than the bill amount by " + balance.negate() + ".");
        if (balance.signum() > 0 && customerId == null) throw ApiException.bad("Choose a customer for a bill with an amount due.");

        String invoiceNo = numbers.next(config.get("invoice.prefix", "INV"), clock.today());
        long saleId = db.insert("""
                INSERT INTO sale (invoice_no, business_date, customer_id, rate_set_id, items_total, discount, taxable_total,
                                  gst_total, exchange_total, round_off, net_payable, paid_total, balance_due, status, notes, created_by)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?, 'FINAL', ?, ?)""",
                invoiceNo, clock.today(), customerId, q.rateSet().get("id"), q.itemsTotal(), q.discount(), q.taxable(),
                q.gst(), q.exchangeTotal(), q.roundOff(), q.netPayable(), Num.r(paid), balance, strOrNull(b.get("notes")),
                CurrentUser.usernameOrSystem());

        for (Map<String, Object> l : q.lines()) {
            db.update("""
                    INSERT INTO sale_line (sale_id, item_id, description, metal, purity_code, quantity, net_wt, rate, metal_value,
                        wastage_value, making_value, stone_value, discount, taxable, gst_pct, gst, line_total, huid)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                    saleId, l.get("item_id"), l.get("description"), l.get("metal"), l.get("purity_code"), l.get("quantity"),
                    l.get("net_wt"), l.get("rate"), l.get("metal_value"), l.get("wastage_value"), l.get("making_value"),
                    l.get("stone_value"), l.get("discount"), l.get("taxable"), l.get("gst_pct"), l.get("gst"),
                    l.get("line_total"), l.get("huid"));
            stock.post(new StockLedger.Move(Rows.id(l.get("item_id")), "SALE", -Rows.integer(l.get("quantity"), 1),
                    "IN_STOCK", "SOLD", null, "SALE", saleId, invoiceNo));
        }
        for (Map<String, Object> x : q.exchange()) {
            db.update("""
                    INSERT INTO sale_exchange (sale_id, description, metal, purity_code, gross_wt, net_wt, fine_wt, rate,
                                               deduction_pct, exchange_value) VALUES (?,?,?,?,?,?,?,?,?,?)""",
                    saleId, x.get("description"), x.get("metal"), x.get("purity_code"), x.get("gross_wt"), x.get("net_wt"),
                    x.get("fine_wt"), x.get("rate"), x.get("deduction_pct"), x.get("value"));
            ledgers.post((String) x.get("metal"), customerId, "SALE", saleId, (BigDecimal) x.get("fine_wt"), Num.ZERO,
                    "Exchange on " + invoiceNo + ": " + x.get("description"));
        }

        if (customerId != null) ledgers.post("PARTY", customerId, "SALE", saleId, q.netPayable(), Num.ZERO, "Bill " + invoiceNo);
        for (Map<String, Object> p : payments) {
            ledgers.payment("SALE", saleId, customerId, "IN", str(p.get("mode")).toUpperCase(), Num.of(p.get("amount")),
                    strOrNull(p.get("reference")), "Bill " + invoiceNo);
        }
        audit.log("SALE", "sale", invoiceNo, q.lines().size() + " items, net " + q.netPayable());

        Map<String, Object> out = get(saleId);
        List<String> warnings = new ArrayList<>();
        BigDecimal cashLimit = config.limit("cash.limit.sale");
        if (cashLimit != null && cashIn.compareTo(cashLimit) > 0) {
            warnings.add("Cash received " + cashIn + " is above the configured limit " + cashLimit + ".");
        }
        BigDecimal panLimit = config.limit("kyc.pan.threshold");
        if (panLimit != null && q.netPayable().compareTo(panLimit) >= 0 && (customer == null || customer.get("pan") == null)) {
            warnings.add("Bill is above the PAN threshold " + panLimit + " but the customer has no PAN on record.");
        }
        out.put("warnings", warnings);
        return out;
    }

    public Map<String, Object> get(long id) {
        Map<String, Object> s = new LinkedHashMap<>(db.one("""
                SELECT s.*, p.name AS customer_name, p.phone AS customer_phone, p.address AS customer_address,
                       p.gstin AS customer_gstin, p.pan AS customer_pan
                FROM sale s LEFT JOIN party p ON p.id = s.customer_id WHERE s.id = ?""", "Bill not found", id));
        s.put("lines", db.rows("""
                SELECT l.*, i.tag_code, i.gross_wt, i.stone_wt FROM sale_line l JOIN item i ON i.id = l.item_id
                WHERE l.sale_id = ? ORDER BY l.id""", id));
        s.put("exchange", db.rows("SELECT * FROM sale_exchange WHERE sale_id = ? ORDER BY id", id));
        s.put("payments", db.rows("SELECT * FROM payment WHERE doc_type IN ('SALE','RETURN') AND doc_id = ? ORDER BY id", id));
        s.put("rate_set", rates.get(Rows.id(s.get("rate_set_id"))));
        Map<String, String> shop = new LinkedHashMap<>();
        for (String k : List.of("shop.name", "shop.address", "shop.phone", "shop.gstin")) shop.put(k.substring(5), config.get(k, ""));
        s.put("shop", shop);
        return s;
    }

    public List<Map<String, Object>> list(java.time.LocalDate from, java.time.LocalDate to, String q) {
        String like = "%" + (q == null ? "" : q.trim().toLowerCase()) + "%";
        return db.rows("""
                SELECT s.*, p.name AS customer_name, (SELECT COUNT(*) FROM sale_line l WHERE l.sale_id = s.id) AS item_count
                FROM sale s LEFT JOIN party p ON p.id = s.customer_id
                WHERE s.business_date BETWEEN ? AND ? AND (LOWER(s.invoice_no) LIKE ? OR LOWER(COALESCE(p.name, '')) LIKE ?
                      OR COALESCE(p.phone, '') LIKE ?)
                ORDER BY s.id DESC""", from, to, like, like, like);
    }

    /** Full return of a bill: items back to stock, money refunded, customer account reversed. */
    @Transactional
    public Map<String, Object> returnSale(long id, String reason, String refundMode) {
        CurrentUser.require(Permission.SALE_RETURN);
        Map<String, Object> s = db.one("SELECT * FROM sale WHERE id = ?", "Bill not found", id);
        if (!"FINAL".equals(s.get("status"))) throw ApiException.conflict("This bill is already returned.");
        if (str(reason).isEmpty()) throw ApiException.bad("Give a reason for the return.");
        Long customerId = Rows.idOrNull(s.get("customer_id"));
        String invoiceNo = (String) s.get("invoice_no");
        for (Map<String, Object> l : db.rows("SELECT * FROM sale_line WHERE sale_id = ?", id)) {
            stock.post(new StockLedger.Move(Rows.id(l.get("item_id")), "SALE_RETURN", Rows.integer(l.get("quantity"), 1),
                    "SOLD", "IN_STOCK", null, "SALE_RETURN", id, reason));
        }
        BigDecimal paid = Num.of(s.get("paid_total"));
        BigDecimal exchange = Num.of(s.get("exchange_total"));
        if (customerId != null) ledgers.post("PARTY", customerId, "RETURN", id, Num.ZERO, Num.of(s.get("net_payable")), "Return of " + invoiceNo);
        // The customer gets back what they paid plus the value of the old metal they exchanged.
        ledgers.payment("RETURN", id, customerId, "OUT", refundMode == null ? "CASH" : refundMode.toUpperCase(),
                Num.r(paid.add(exchange)), null, "Refund for " + invoiceNo);
        if (customerId != null && exchange.signum() > 0) {
            ledgers.post("PARTY", customerId, "RETURN", id, Num.ZERO, exchange, "Exchange value on returned " + invoiceNo);
        }
        db.update("UPDATE sale SET status = 'RETURNED', notes = ? WHERE id = ?",
                (s.get("notes") == null ? "" : s.get("notes") + " | ") + "Returned: " + reason, id);
        audit.log("SALE_RETURN", "sale", invoiceNo, reason);
        return get(id);
    }
}
