package com.swarnos.reports;

import com.swarnos.auth.CurrentUser;
import com.swarnos.auth.Permission;
import com.swarnos.common.ApiException;
import com.swarnos.common.BusinessClock;
import com.swarnos.common.Db;
import com.swarnos.common.Num;
import com.swarnos.common.Rows;
import com.swarnos.items.ItemService;
import com.swarnos.ledger.LedgerService;
import com.swarnos.rates.RateService;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import org.springframework.stereotype.Service;

/**
 * Reports (BRD §12). Each report returns a title, column list and rows so the
 * screen, CSV export and print view all share one definition.
 */
@Service
public class ReportService {
    public record Column(String key, String label, String type) {}

    public record Report(String title, List<Column> columns, List<Map<String, Object>> rows, Map<String, Object> totals) {}

    public static final Map<String, String> CATALOGUE = new LinkedHashMap<>();

    static {
        CATALOGUE.put("stock_summary", "Stock summary by category");
        CATALOGUE.put("stock_metal", "Stock by metal and purity");
        CATALOGUE.put("stock_ageing", "Stock ageing");
        CATALOGUE.put("tag_stock", "Tag-wise stock");
        CATALOGUE.put("sales_register", "Sales register");
        CATALOGUE.put("sales_items", "Item-wise sales");
        CATALOGUE.put("sales_by_category", "Sales by category");
        CATALOGUE.put("sales_by_salesperson", "Sales by salesperson");
        CATALOGUE.put("purchase_register", "Purchase register");
        CATALOGUE.put("purchase_by_mode", "Purchases by mode (cash / bank / gold / silver)");
        CATALOGUE.put("purchase_by_class", "Purchases by class (Seen / Unseen)");
        CATALOGUE.put("old_metal", "Old metal bought and exchanged");
        CATALOGUE.put("outstanding", "Customer and vendor outstanding");
        CATALOGUE.put("repairs_open", "Open and overdue repairs");
        CATALOGUE.put("repairs_karigar", "Karigar-wise metal difference");
        CATALOGUE.put("tally_history", "Daily tally and variance");
        CATALOGUE.put("rate_history", "Metal rate history");
        CATALOGUE.put("gst_summary", "GST summary (sales)");
        CATALOGUE.put("huid_register", "HUID / hallmark register");
        CATALOGUE.put("backup_log", "Backup log");
    }

    private final Db db;
    private final ItemService items;
    private final RateService rates;
    private final LedgerService ledgers;
    private final BusinessClock clock;

    public ReportService(Db db, ItemService items, RateService rates, LedgerService ledgers, BusinessClock clock) {
        this.db = db;
        this.items = items;
        this.rates = rates;
        this.ledgers = ledgers;
        this.clock = clock;
    }

    public Report run(String name, LocalDate from, LocalDate to) {
        boolean canClass = CurrentUser.can(Permission.VIEW_PURCHASE_CLASS);
        return switch (name) {
            case "stock_summary" -> stockGrouped("Stock summary by category", "category_name", "Category");
            case "stock_metal" -> stockGrouped("Stock by metal and purity", "metal_purity", "Metal / purity");
            case "stock_ageing" -> ageing();
            case "tag_stock" -> tagStock(canClass);
            case "sales_register" -> table("Sales register", db.rows("""
                    SELECT s.invoice_no, s.business_date, p.name AS customer, s.items_total, s.discount, s.gst_total,
                           s.exchange_total, s.net_payable, s.paid_total, s.balance_due, s.status, s.created_by
                    FROM sale s LEFT JOIN party p ON p.id = s.customer_id WHERE s.business_date BETWEEN ? AND ?
                    ORDER BY s.id""", from, to),
                    cols("invoice_no:Invoice", "business_date:Date:date", "customer:Customer", "items_total:Items:money",
                            "discount:Discount:money", "gst_total:GST:money", "exchange_total:Exchange:money",
                            "net_payable:Net:money", "paid_total:Paid:money", "balance_due:Due:money", "status:Status",
                            "created_by:By"));
            case "sales_items" -> table("Item-wise sales", db.rows("""
                    SELECT s.invoice_no, s.business_date, i.tag_code, l.description, l.net_wt, l.rate, l.making_value,
                           l.stone_value, l.discount, l.gst, l.line_total, s.status
                    FROM sale_line l JOIN sale s ON s.id = l.sale_id JOIN item i ON i.id = l.item_id
                    WHERE s.business_date BETWEEN ? AND ? ORDER BY s.id, l.id""", from, to),
                    cols("invoice_no:Invoice", "business_date:Date:date", "tag_code:Tag", "description:Item", "net_wt:Net g:wt",
                            "rate:Rate/g:money", "making_value:Making:money", "stone_value:Stones:money",
                            "discount:Discount:money", "gst:GST:money", "line_total:Total:money", "status:Status"));
            case "sales_by_category" -> table("Sales by category", db.rows("""
                    SELECT c.name AS category, COUNT(*) AS pieces, SUM(l.net_wt) AS net_wt, SUM(l.taxable) AS taxable,
                           SUM(l.gst) AS gst, SUM(l.line_total) AS total
                    FROM sale_line l JOIN sale s ON s.id = l.sale_id JOIN item i ON i.id = l.item_id
                    JOIN category c ON c.id = i.category_id
                    WHERE s.status = 'FINAL' AND s.business_date BETWEEN ? AND ? GROUP BY c.name ORDER BY total DESC""", from, to),
                    cols("category:Category", "pieces:Pieces:int", "net_wt:Net g:wt", "taxable:Taxable:money", "gst:GST:money",
                            "total:Total:money"));
            case "sales_by_salesperson" -> table("Sales by salesperson", db.rows("""
                    SELECT s.created_by AS salesperson, COUNT(*) AS bills, SUM(s.net_payable) AS net, SUM(s.discount) AS discount
                    FROM sale s WHERE s.status = 'FINAL' AND s.business_date BETWEEN ? AND ?
                    GROUP BY s.created_by ORDER BY net DESC""", from, to),
                    cols("salesperson:Salesperson", "bills:Bills:int", "net:Net sales:money", "discount:Discount given:money"));
            case "purchase_register" -> {
                List<Map<String, Object>> rows = db.rows("""
                        SELECT p.purchase_no, p.business_date, pa.name AS party, p.purchase_kind, p.payment_mode, p.purchase_class,
                               p.gst_invoice_no, p.taxable_amount, p.gst_amount, p.total_amount, p.cash_paid, p.bank_paid,
                               p.gold_fine_paid, p.silver_fine_paid, p.balance_due
                        FROM purchase p LEFT JOIN party pa ON pa.id = p.party_id WHERE p.business_date BETWEEN ? AND ?
                        ORDER BY p.id""", from, to);
                List<Column> c = new ArrayList<>(cols("purchase_no:No", "business_date:Date:date", "party:Party",
                        "purchase_kind:Type", "payment_mode:Mode"));
                if (canClass) c.add(new Column("purchase_class", "Class", "text"));
                c.addAll(cols("gst_invoice_no:GST inv", "taxable_amount:Taxable:money", "gst_amount:GST:money",
                        "total_amount:Total:money", "cash_paid:Cash:money", "bank_paid:Bank:money", "gold_fine_paid:Gold fine g:wt",
                        "silver_fine_paid:Silver fine g:wt", "balance_due:Due:money"));
                if (!canClass) rows.forEach(r -> r.remove("purchase_class"));
                yield table("Purchase register", rows, c);
            }
            case "purchase_by_mode" -> table("Purchases by mode", db.rows("""
                    SELECT payment_mode, COUNT(*) AS purchases, SUM(total_amount) AS total, SUM(cash_paid) AS cash,
                           SUM(bank_paid) AS bank, SUM(gold_fine_paid) AS gold_fine, SUM(silver_fine_paid) AS silver_fine,
                           SUM(balance_due) AS due
                    FROM purchase WHERE business_date BETWEEN ? AND ? GROUP BY payment_mode ORDER BY payment_mode""", from, to),
                    cols("payment_mode:Mode", "purchases:Purchases:int", "total:Total:money", "cash:Cash:money", "bank:Bank:money",
                            "gold_fine:Gold fine g:wt", "silver_fine:Silver fine g:wt", "due:Due:money"));
            case "purchase_by_class" -> {
                CurrentUser.require(Permission.VIEW_PURCHASE_CLASS);
                yield table("Purchases by class (Seen / Unseen)", db.rows("""
                        SELECT purchase_class, COUNT(*) AS purchases, SUM(taxable_amount) AS taxable, SUM(gst_amount) AS gst,
                               SUM(total_amount) AS total, SUM(cash_paid) AS cash_out, SUM(bank_paid) AS bank_out,
                               (SELECT COUNT(*) FROM item i WHERE i.purchase_class = p.purchase_class AND i.status = 'IN_STOCK') AS pieces_in_stock
                        FROM purchase p WHERE business_date BETWEEN ? AND ? GROUP BY purchase_class ORDER BY purchase_class""", from, to),
                        cols("purchase_class:Class", "purchases:Purchases:int", "taxable:Taxable:money", "gst:GST:money",
                                "total:Total:money", "cash_out:Cash paid:money", "bank_out:Bank paid:money",
                                "pieces_in_stock:Pieces in stock now:int"));
            }
            case "old_metal" -> table("Old metal bought and exchanged", db.rows("""
                    SELECT 'PURCHASE' AS source, p.purchase_no AS doc_no, p.business_date, l.metal, l.purity_code, l.gross_wt,
                           l.net_wt, l.fine_wt, l.deduction_pct, l.amount AS amount
                    FROM purchase_line l JOIN purchase p ON p.id = l.purchase_id
                    WHERE p.purchase_kind = 'OLD_METAL' AND p.business_date BETWEEN ? AND ?
                    UNION ALL
                    SELECT 'EXCHANGE', s.invoice_no, s.business_date, x.metal, x.purity_code, x.gross_wt, x.net_wt, x.fine_wt,
                           x.deduction_pct, x.exchange_value
                    FROM sale_exchange x JOIN sale s ON s.id = x.sale_id WHERE s.business_date BETWEEN ? AND ?
                    ORDER BY business_date""", from, to, from, to),
                    cols("source:Source", "doc_no:Document", "business_date:Date:date", "metal:Metal", "purity_code:Purity",
                            "gross_wt:Gross g:wt", "net_wt:Net g:wt", "fine_wt:Fine g:wt", "deduction_pct:Deduction %:num",
                            "amount:Value:money"));
            case "outstanding" -> {
                CurrentUser.require(Permission.REPORTS_LEDGER);
                yield table("Customer and vendor outstanding", db.rows("""
                        SELECT p.name, p.party_type, p.phone, SUM(e.debit - e.credit) AS balance
                        FROM ledger_entry e JOIN party p ON p.id = e.party_id WHERE e.book = 'PARTY'
                        GROUP BY p.id, p.name, p.party_type, p.phone HAVING SUM(e.debit - e.credit) <> 0 ORDER BY balance DESC"""),
                        cols("name:Party", "party_type:Type", "phone:Phone", "balance:Balance (+ they owe us / - we owe):money"));
            }
            case "repairs_open" -> table("Open and overdue repairs", db.rows("""
                    SELECT r.job_no, c.name AS customer, c.phone, r.description, r.weight_in, r.status, r.promised_date,
                           k.name AS karigar, CASE WHEN r.promised_date < ? THEN 'OVERDUE' ELSE '' END AS flag
                    FROM repair_job r JOIN party c ON c.id = r.customer_id LEFT JOIN party k ON k.id = r.karigar_id
                    WHERE r.status <> 'DELIVERED' ORDER BY r.promised_date""", clock.today()),
                    cols("job_no:Job", "customer:Customer", "phone:Phone", "description:Item", "weight_in:Weight in g:wt",
                            "status:Status", "promised_date:Promised:date", "karigar:Karigar", "flag:Flag"));
            case "repairs_karigar" -> table("Karigar-wise metal difference", db.rows("""
                    SELECT k.name AS karigar, COUNT(*) AS jobs, SUM(r.weight_issued) AS issued, SUM(r.weight_returned) AS returned,
                           SUM(r.weight_returned - r.weight_issued) AS difference
                    FROM repair_job r JOIN party k ON k.id = r.karigar_id WHERE r.weight_returned IS NOT NULL
                    GROUP BY k.name ORDER BY k.name"""),
                    cols("karigar:Karigar", "jobs:Jobs:int", "issued:Issued g:wt", "returned:Returned g:wt", "difference:Difference g:wt"));
            case "tally_history" -> table("Daily tally and variance", db.rows("""
                    SELECT t.id, t.business_date, l.name AS location, c.name AS category, t.status, t.expected_count,
                           (SELECT COUNT(*) FROM tally_scan s WHERE s.session_id = t.id AND s.item_id IS NOT NULL) AS scanned,
                           (SELECT COUNT(*) FROM tally_variance v WHERE v.session_id = t.id AND v.kind = 'MISSING') AS missing,
                           (SELECT COUNT(*) FROM tally_variance v WHERE v.session_id = t.id AND v.resolution = 'MARK_LOST') AS marked_lost,
                           t.opened_by, t.closed_by
                    FROM tally_session t LEFT JOIN location l ON l.id = t.location_id LEFT JOIN category c ON c.id = t.category_id
                    WHERE t.business_date BETWEEN ? AND ? ORDER BY t.id DESC""", from, to),
                    cols("id:Session:int", "business_date:Date:date", "location:Location", "category:Category", "status:Status",
                            "expected_count:Expected:int", "scanned:Scanned:int", "missing:Missing:int", "marked_lost:Marked lost:int",
                            "opened_by:Opened by", "closed_by:Closed by"));
            case "rate_history" -> table("Metal rate history", db.rows("""
                    SELECT business_date, source, provider, gold_24k, silver_base, platinum_base, status, entered_by, approved_by
                    FROM rate_set WHERE business_date BETWEEN ? AND ? ORDER BY id DESC""", from, to),
                    cols("business_date:Date:date", "source:Source", "provider:Provider", "gold_24k:Gold 24K /g:money",
                            "silver_base:Silver /g:money", "platinum_base:Platinum /g:money", "status:Status",
                            "entered_by:Entered by", "approved_by:Approved by"));
            case "gst_summary" -> table("GST summary (sales)", db.rows("""
                    SELECT l.gst_pct, COUNT(*) AS lines, SUM(l.taxable) AS taxable, SUM(l.gst) AS gst,
                           SUM(l.gst) / 2 AS cgst, SUM(l.gst) / 2 AS sgst
                    FROM sale_line l JOIN sale s ON s.id = l.sale_id
                    WHERE s.status = 'FINAL' AND s.business_date BETWEEN ? AND ? GROUP BY l.gst_pct ORDER BY l.gst_pct""", from, to),
                    cols("gst_pct:GST %:num", "lines:Lines:int", "taxable:Taxable:money", "gst:GST:money", "cgst:CGST:money",
                            "sgst:SGST:money"));
            case "huid_register" -> table("HUID / hallmark register", db.rows("""
                    SELECT i.tag_code, i.huid, i.name, i.purity_code, i.net_wt, i.status,
                           (SELECT s.invoice_no FROM sale_line l JOIN sale s ON s.id = l.sale_id WHERE l.item_id = i.id
                            ORDER BY s.id DESC LIMIT 1) AS invoice_no
                    FROM item i WHERE i.huid IS NOT NULL ORDER BY i.tag_code"""),
                    cols("tag_code:Tag", "huid:HUID", "name:Item", "purity_code:Purity", "net_wt:Net g:wt", "status:Status",
                            "invoice_no:Sold on"));
            case "backup_log" -> table("Backup log", db.rows("SELECT * FROM backup_log ORDER BY id DESC"),
                    cols("at:Time:datetime", "username:By", "file_name:File", "target:Saved to", "size_bytes:Bytes:int",
                            "row_count:Rows:int", "sha256:SHA-256", "verified:Verified"));
            default -> throw ApiException.notFound("Unknown report " + name);
        };
    }

    private Report stockGrouped(String title, String key, String label) {
        List<Map<String, Object>> all = inStock();
        Map<String, Map<String, Object>> groups = new TreeMap<>();
        for (Map<String, Object> i : all) {
            String k = key.equals("metal_purity")
                    ? (i.get("metal") == null ? "Gifting" : i.get("metal") + " " + i.get("purity_code"))
                    : (String) i.get("category_name");
            Map<String, Object> g = groups.computeIfAbsent(k, x -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("group", x);
                m.put("pieces", 0L);
                m.put("gross_wt", Num.ZERO);
                m.put("net_wt", Num.ZERO);
                m.put("stone_carat", Num.ZERO);
                m.put("value", Num.ZERO);
                return m;
            });
            g.put("pieces", (Long) g.get("pieces") + Rows.integer(i.get("quantity"), 1));
            g.put("gross_wt", ((BigDecimal) g.get("gross_wt")).add(Num.of(i.get("gross_wt"))));
            g.put("net_wt", ((BigDecimal) g.get("net_wt")).add(Num.of(i.get("net_wt"))));
            g.put("stone_carat", ((BigDecimal) g.get("stone_carat")).add(Num.of(i.get("stone_carat"))));
            if (i.get("price") != null) g.put("value", ((BigDecimal) g.get("value")).add((BigDecimal) i.get("price")));
        }
        List<Map<String, Object>> rows = new ArrayList<>(groups.values());
        Map<String, Object> totals = sum(rows, "pieces", "gross_wt", "net_wt", "stone_carat", "value");
        return new Report(title, cols("group:" + label, "pieces:Pieces:int", "gross_wt:Gross g:wt", "net_wt:Net g:wt",
                "stone_carat:Stone ct:wt", "value:Value at today's rate:money"), rows, totals);
    }

    private Report ageing() {
        LocalDate today = clock.today();
        String[] buckets = {"0-30 days", "31-90 days", "91-180 days", "181-365 days", "Over 1 year"};
        Map<String, Map<String, Object>> groups = new LinkedHashMap<>();
        for (String b : buckets) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("bucket", b);
            m.put("pieces", 0L);
            m.put("net_wt", Num.ZERO);
            m.put("value", Num.ZERO);
            groups.put(b, m);
        }
        for (Map<String, Object> i : inStock()) {
            long days = ChronoUnit.DAYS.between(Rows.date(i.get("created_at")), today);
            String b = days <= 30 ? buckets[0] : days <= 90 ? buckets[1] : days <= 180 ? buckets[2] : days <= 365 ? buckets[3] : buckets[4];
            Map<String, Object> g = groups.get(b);
            g.put("pieces", (Long) g.get("pieces") + 1);
            g.put("net_wt", ((BigDecimal) g.get("net_wt")).add(Num.of(i.get("net_wt"))));
            if (i.get("price") != null) g.put("value", ((BigDecimal) g.get("value")).add((BigDecimal) i.get("price")));
        }
        List<Map<String, Object>> rows = new ArrayList<>(groups.values());
        return new Report("Stock ageing", cols("bucket:Age", "pieces:Pieces:int", "net_wt:Net g:wt", "value:Value:money"),
                rows, sum(rows, "pieces", "net_wt", "value"));
    }

    private Report tagStock(boolean canClass) {
        List<Map<String, Object>> rows = inStock();
        List<Column> c = new ArrayList<>(cols("tag_code:Tag", "category_name:Category", "name:Item", "purity_code:Purity",
                "gross_wt:Gross g:wt", "net_wt:Net g:wt", "stone_carat:Stone ct:wt", "location_name:Location",
                "huid:HUID", "price:Price today:money"));
        if (canClass) c.add(new Column("purchase_class", "Class", "text"));
        return new Report("Tag-wise stock", c, rows, sum(rows, "gross_wt", "net_wt", "price"));
    }

    private List<Map<String, Object>> inStock() {
        return items.search(new ItemService.ItemFilter(null, "IN_STOCK", null, null, null, null, null, null, null, null,
                null, null, null, 100000));
    }

    private static Report table(String title, List<Map<String, Object>> rows, List<Column> columns) {
        String[] numeric = columns.stream().filter(c -> c.type().equals("money") || c.type().equals("wt") || c.type().equals("int"))
                .map(Column::key).toArray(String[]::new);
        return new Report(title, columns, rows, sum(rows, numeric));
    }

    private static Map<String, Object> sum(List<Map<String, Object>> rows, String... keys) {
        Map<String, Object> totals = new LinkedHashMap<>();
        for (String k : keys) {
            BigDecimal t = Num.ZERO;
            for (Map<String, Object> r : rows) if (r.get(k) instanceof Number n) t = t.add(new BigDecimal(n.toString()));
            totals.put(k, Num.r(t));
        }
        return totals;
    }

    static List<Column> cols(String... specs) {
        List<Column> out = new ArrayList<>();
        for (String s : specs) {
            String[] p = s.split(":");
            out.add(new Column(p[0], p[1], p.length > 2 ? p[2] : "text"));
        }
        return out;
    }

    // ---------- dashboard ----------

    public Map<String, Object> dashboard() {
        LocalDate today = clock.today();
        Map<String, Object> d = new LinkedHashMap<>();
        d.put("business_date", today.toString());
        d.put("rate", rates.today());
        d.put("sales_today", db.one("""
                SELECT COUNT(*) AS bills, COALESCE(SUM(net_payable), 0) AS net, COALESCE(SUM(gst_total), 0) AS gst,
                       COALESCE((SELECT COUNT(*) FROM sale_line l JOIN sale s2 ON s2.id = l.sale_id
                                 WHERE s2.business_date = ? AND s2.status = 'FINAL'), 0) AS pieces
                FROM sale WHERE business_date = ? AND status = 'FINAL'""", "", today, today));
        d.put("purchases_today", db.one("""
                SELECT COUNT(*) AS purchases, COALESCE(SUM(total_amount), 0) AS total FROM purchase WHERE business_date = ?""",
                "", today));
        List<Map<String, Object>> stock = inStock();
        Map<String, Map<String, Object>> byMetal = new TreeMap<>();
        BigDecimal value = Num.ZERO;
        long pieces = 0;
        for (Map<String, Object> i : stock) {
            String metal = i.get("metal") == null ? "GIFTING" : (String) i.get("metal");
            Map<String, Object> g = byMetal.computeIfAbsent(metal, m -> new LinkedHashMap<>(Map.of("metal", m, "pieces", 0L,
                    "net_wt", Num.ZERO, "value", Num.ZERO)));
            g.put("pieces", (Long) g.get("pieces") + Rows.integer(i.get("quantity"), 1));
            g.put("net_wt", ((BigDecimal) g.get("net_wt")).add(Num.of(i.get("net_wt"))));
            if (i.get("price") != null) {
                g.put("value", ((BigDecimal) g.get("value")).add((BigDecimal) i.get("price")));
                value = value.add((BigDecimal) i.get("price"));
            }
            pieces += Rows.integer(i.get("quantity"), 1);
        }
        d.put("stock", Map.of("pieces", pieces, "value", Num.r(value), "by_metal", byMetal.values()));
        d.put("repairs", db.one("""
                SELECT COALESCE(SUM(CASE WHEN status <> 'DELIVERED' THEN 1 ELSE 0 END), 0) AS open,
                       COALESCE(SUM(CASE WHEN status = 'READY' THEN 1 ELSE 0 END), 0) AS ready,
                       COALESCE(SUM(CASE WHEN status <> 'DELIVERED' AND promised_date < ? THEN 1 ELSE 0 END), 0) AS overdue
                FROM repair_job""", "", today));
        d.put("tally", db.opt("SELECT * FROM tally_session ORDER BY id DESC").orElse(null));
        if (CurrentUser.can(Permission.REPORTS_LEDGER)) {
            Map<String, Object> books = new LinkedHashMap<>();
            for (String b : LedgerService.BOOKS) books.put(b, ledgers.balance(b));
            d.put("books", books);
        }
        d.put("recent_sales", db.rows("""
                SELECT s.id, s.invoice_no, s.net_payable, s.created_at, p.name AS customer_name FROM sale s
                LEFT JOIN party p ON p.id = s.customer_id ORDER BY s.id DESC LIMIT 6"""));
        List<String> alerts = new ArrayList<>();
        if (rates.approvedToday().isEmpty()) alerts.add("Today's metal rate is not approved - billing is paused until it is.");
        long openTally = db.value("SELECT COUNT(*) FROM tally_session WHERE status = 'OPEN'", Long.class);
        if (openTally > 0) alerts.add(openTally + " stock tally session(s) still open.");
        long tallyToday = db.value("SELECT COUNT(*) FROM tally_session WHERE business_date = ?", Long.class, today);
        if (tallyToday == 0) alerts.add("No stock tally done today yet.");
        long overdue = Rows.integer(((Map<?, ?>) d.get("repairs")).get("overdue"), 0);
        if (overdue > 0) alerts.add(overdue + " repair job(s) are past their promised date.");
        long mismatch = db.value("""
                SELECT COUNT(*) FROM item i LEFT JOIN stock_movement m ON m.id = (SELECT MAX(id) FROM stock_movement WHERE item_id = i.id)
                WHERE m.status_after IS NULL OR m.status_after <> i.status""", Long.class);
        if (mismatch > 0) alerts.add(mismatch + " item(s) differ from the stock ledger - check Inventory > Ledger check.");
        long lastBackupDays = db.opt("SELECT at FROM backup_log ORDER BY id DESC")
                .map(r -> ChronoUnit.DAYS.between(Rows.date(r.get("at")), today)).orElse(999L);
        if (lastBackupDays > 1) alerts.add(lastBackupDays == 999 ? "No backup taken yet - take one to USB from Settings > Backup."
                : "Last backup was " + lastBackupDays + " days ago.");
        d.put("alerts", alerts);
        return d;
    }
}
