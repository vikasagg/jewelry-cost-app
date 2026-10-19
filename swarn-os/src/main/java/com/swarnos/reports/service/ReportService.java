package com.swarnos.reports.service;

import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.inventory.domain.Item;
import com.swarnos.inventory.service.ItemService;
import com.swarnos.reports.domain.Column;
import com.swarnos.reports.domain.ReportCatalogue;
import com.swarnos.reports.domain.ReportTable;
import com.swarnos.reports.repository.ReportRepository;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.function.Function;
import org.springframework.stereotype.Service;

/** Runs the reports of BRD §12 and applies who may see what. */
@Service
public class ReportService {
    private static final String[] AGE_BUCKETS = {"0-30 days", "31-90 days", "91-180 days", "181-365 days", "Over 1 year"};

    private final ReportRepository reports;
    private final ItemService items;
    private final BusinessClock clock;

    public ReportService(ReportRepository reports, ItemService items, BusinessClock clock) {
        this.reports = reports;
        this.items = items;
        this.clock = clock;
    }

    public Map<String, String> catalogue() {
        return ReportCatalogue.REPORTS;
    }

    public ReportTable run(String name, LocalDate from, LocalDate to) {
        boolean seesClass = CurrentUser.can(Permission.VIEW_PURCHASE_CLASS);
        return switch (name) {
            case "stock_summary" -> stockGrouped("Stock summary by category", "Category", i -> i.listing().categoryName());
            case "stock_metal" -> stockGrouped("Stock by metal and purity", "Metal / purity",
                    i -> i.listing().item().metal() == null ? "Gifting" : i.listing().item().metal() + " " + i.listing().item().purityCode());
            case "stock_ageing" -> ageing();
            case "tag_stock" -> tagStock(seesClass);
            case "sales_register" -> ReportTable.of("Sales register", reports.salesRegister(from, to),
                    "invoice_no:Invoice", "business_date:Date:date", "customer:Customer", "items_total:Items:money",
                    "discount:Discount:money", "gst_total:GST:money", "exchange_total:Exchange:money", "net_payable:Net:money",
                    "paid_total:Paid:money", "balance_due:Due:money", "status:Status", "created_by:By");
            case "sales_items" -> ReportTable.of("Item-wise sales", reports.salesItems(from, to),
                    "invoice_no:Invoice", "business_date:Date:date", "tag_code:Tag", "description:Item", "net_wt:Net g:wt",
                    "rate:Rate/g:money", "making_value:Making:money", "stone_value:Stones:money", "discount:Discount:money",
                    "gst:GST:money", "line_total:Total:money", "status:Status");
            case "sales_by_category" -> ReportTable.of("Sales by category", reports.salesByCategory(from, to),
                    "category:Category", "pieces:Pieces:int", "net_wt:Net g:wt", "taxable:Taxable:money", "gst:GST:money", "total:Total:money");
            case "sales_by_salesperson" -> ReportTable.of("Sales by salesperson", reports.salesBySalesperson(from, to),
                    "salesperson:Salesperson", "bills:Bills:int", "net:Net sales:money", "discount:Discount given:money");
            case "purchase_register" -> purchaseRegister(from, to, seesClass);
            case "purchase_by_mode" -> ReportTable.of("Purchases by mode", reports.purchaseByMode(from, to),
                    "payment_mode:Mode", "purchases:Purchases:int", "total:Total:money", "cash:Cash:money", "bank:Bank:money",
                    "gold_fine:Gold fine g:wt", "silver_fine:Silver fine g:wt", "due:Due:money");
            case "purchase_by_class" -> {
                CurrentUser.require(Permission.VIEW_PURCHASE_CLASS);
                yield ReportTable.of("Purchases by class (Seen / Unseen)", reports.purchaseByClass(from, to),
                        "purchase_class:Class", "purchases:Purchases:int", "taxable:Taxable:money", "gst:GST:money", "total:Total:money",
                        "cash_out:Cash paid:money", "bank_out:Bank paid:money", "pieces_in_stock:Pieces in stock now:int");
            }
            case "old_metal" -> ReportTable.of("Old metal bought and exchanged", reports.oldMetal(from, to),
                    "source:Source", "doc_no:Document", "business_date:Date:date", "metal:Metal", "purity_code:Purity",
                    "gross_wt:Gross g:wt", "net_wt:Net g:wt", "fine_wt:Fine g:wt", "deduction_pct:Deduction %:num", "amount:Value:money");
            case "outstanding" -> {
                CurrentUser.require(Permission.REPORTS_LEDGER);
                yield ReportTable.of("Customer and vendor outstanding", reports.outstanding(), "name:Party", "party_type:Type",
                        "phone:Phone", "balance:Balance (+ they owe us / - we owe):money");
            }
            case "repairs_open" -> ReportTable.of("Open and overdue repairs", reports.openRepairs(clock.today()),
                    "job_no:Job", "customer:Customer", "phone:Phone", "description:Item", "weight_in:Weight in g:wt", "status:Status",
                    "promised_date:Promised:date", "karigar:Karigar", "flag:Flag");
            case "repairs_karigar" -> ReportTable.of("Karigar-wise metal difference", reports.karigarDifference(),
                    "karigar:Karigar", "jobs:Jobs:int", "issued:Issued g:wt", "returned:Returned g:wt", "difference:Difference g:wt");
            case "tally_history" -> ReportTable.of("Daily tally and variance", reports.tallyHistory(from, to),
                    "id:Session:int", "business_date:Date:date", "location:Location", "category:Category", "status:Status",
                    "expected_count:Expected:int", "scanned:Scanned:int", "missing:Missing:int", "marked_lost:Marked lost:int",
                    "opened_by:Opened by", "closed_by:Closed by");
            case "rate_history" -> ReportTable.of("Metal rate history", reports.rateHistory(from, to),
                    "business_date:Date:date", "source:Source", "provider:Provider", "gold_24k:Gold 24K /g:money",
                    "silver_base:Silver /g:money", "platinum_base:Platinum /g:money", "status:Status", "entered_by:Entered by",
                    "approved_by:Approved by");
            case "gst_summary" -> ReportTable.of("GST summary (sales)", reports.gstSummary(from, to),
                    "gst_pct:GST %:num", "lines:Lines:int", "taxable:Taxable:money", "gst:GST:money", "cgst:CGST:money", "sgst:SGST:money");
            case "huid_register" -> ReportTable.of("HUID / hallmark register", reports.huidRegister(),
                    "tag_code:Tag", "huid:HUID", "name:Item", "purity_code:Purity", "net_wt:Net g:wt", "status:Status", "invoice_no:Sold on");
            case "backup_log" -> {
                CurrentUser.require(Permission.BACKUP);
                yield ReportTable.of("Backup log", reports.backupLog(), "at:Time:datetime", "username:By", "file_name:File",
                        "target:Saved to", "size_bytes:Bytes:int", "row_count:Rows:int", "sha256:SHA-256", "verified:Verified");
            }
            default -> throw BusinessException.notFound("Unknown report " + name);
        };
    }

    private ReportTable purchaseRegister(LocalDate from, LocalDate to, boolean seesClass) {
        List<Map<String, Object>> rows = reports.purchaseRegister(from, to);
        List<String> specs = new ArrayList<>(List.of("purchase_no:No", "business_date:Date:date", "party:Party", "purchase_kind:Type",
                "payment_mode:Mode"));
        if (seesClass) specs.add("purchase_class:Class"); else rows.forEach(r -> r.remove("purchase_class"));
        specs.addAll(List.of("gst_invoice_no:GST inv", "taxable_amount:Taxable:money", "gst_amount:GST:money", "total_amount:Total:money",
                "cash_paid:Cash:money", "bank_paid:Bank:money", "gold_fine_paid:Gold fine g:wt", "silver_fine_paid:Silver fine g:wt",
                "balance_due:Due:money"));
        return ReportTable.of("Purchase register", rows, specs.toArray(String[]::new));
    }

    private ReportTable stockGrouped(String title, String label, Function<ItemService.PricedItem, String> key) {
        Map<String, Map<String, Object>> groups = new TreeMap<>();
        for (ItemService.PricedItem p : items.inStock()) {
            Item i = p.listing().item();
            Map<String, Object> g = groups.computeIfAbsent(key.apply(p), k -> newRow("group", k, "pieces", "gross_wt", "net_wt",
                    "stone_carat", "value"));
            add(g, "pieces", BigDecimal.valueOf(i.quantity()));
            add(g, "gross_wt", i.grossWt());
            add(g, "net_wt", i.netWt());
            add(g, "stone_carat", p.listing().stoneCarat());
            add(g, "value", p.total());
        }
        return ReportTable.of(title, new ArrayList<>(groups.values()), "group:" + label, "pieces:Pieces:int", "gross_wt:Gross g:wt",
                "net_wt:Net g:wt", "stone_carat:Stone ct:wt", "value:Value at today's rate:money");
    }

    private ReportTable ageing() {
        LocalDate today = clock.today();
        Map<String, Map<String, Object>> groups = new LinkedHashMap<>();
        for (String b : AGE_BUCKETS) groups.put(b, newRow("bucket", b, "pieces", "net_wt", "value"));
        for (ItemService.PricedItem p : items.inStock()) {
            Item i = p.listing().item();
            long days = ChronoUnit.DAYS.between(i.createdAt().atZone(ZoneId.systemDefault()).toLocalDate(), today);
            String b = days <= 30 ? AGE_BUCKETS[0] : days <= 90 ? AGE_BUCKETS[1] : days <= 180 ? AGE_BUCKETS[2]
                    : days <= 365 ? AGE_BUCKETS[3] : AGE_BUCKETS[4];
            Map<String, Object> g = groups.get(b);
            add(g, "pieces", BigDecimal.ONE);
            add(g, "net_wt", i.netWt());
            add(g, "value", p.total());
        }
        return ReportTable.of("Stock ageing", new ArrayList<>(groups.values()), "bucket:Age", "pieces:Pieces:int", "net_wt:Net g:wt",
                "value:Value:money");
    }

    private ReportTable tagStock(boolean seesClass) {
        List<Map<String, Object>> rows = new ArrayList<>();
        for (ItemService.PricedItem p : items.inStock()) {
            Item i = p.listing().item();
            Map<String, Object> r = new LinkedHashMap<>();
            r.put("tag_code", i.tagCode());
            r.put("category_name", p.listing().categoryName());
            r.put("name", i.name());
            r.put("purity_code", i.purityCode());
            r.put("gross_wt", i.grossWt());
            r.put("net_wt", i.netWt());
            r.put("stone_carat", p.listing().stoneCarat());
            r.put("location_name", p.listing().locationName());
            r.put("huid", i.huid());
            r.put("price", p.total());
            if (seesClass) r.put("purchase_class", i.purchaseClass());
            rows.add(r);
        }
        List<Column> columns = new ArrayList<>(List.of(Column.of("tag_code:Tag"), Column.of("category_name:Category"), Column.of("name:Item"),
                Column.of("purity_code:Purity"), Column.of("gross_wt:Gross g:wt"), Column.of("net_wt:Net g:wt"),
                Column.of("stone_carat:Stone ct:wt"), Column.of("location_name:Location"), Column.of("huid:HUID"),
                Column.of("price:Price today:money")));
        if (seesClass) columns.add(Column.of("purchase_class:Class"));
        return new ReportTable("Tag-wise stock", columns, rows, ReportTable.totals(rows, List.of("gross_wt", "net_wt", "price")));
    }

    private static Map<String, Object> newRow(String labelKey, String label, String... numericKeys) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put(labelKey, label);
        for (String k : numericKeys) m.put(k, Decimals.ZERO);
        return m;
    }

    private static void add(Map<String, Object> row, String key, BigDecimal value) {
        if (value != null) row.put(key, ((BigDecimal) row.get(key)).add(value));
    }
}
