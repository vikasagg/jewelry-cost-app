package com.swarnos.items;

import static com.swarnos.common.Rows.str;
import static com.swarnos.common.Rows.strOrNull;

import com.swarnos.auth.CurrentUser;
import com.swarnos.auth.Permission;
import com.swarnos.common.ApiException;
import com.swarnos.common.AuditService;
import com.swarnos.common.Db;
import com.swarnos.common.DocNumbers;
import com.swarnos.common.Num;
import com.swarnos.common.Rows;
import com.swarnos.config.ConfigService;
import com.swarnos.rates.RateService;
import com.swarnos.stock.StockLedger;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Item master, tags and live pricing (BRD §3, §4). */
@Service
public class ItemService {
    static final BigDecimal CARAT_TO_GRAM = new BigDecimal("0.2");

    static final String SELECT = """
            SELECT i.*, c.code AS category_code, c.name AS category_name, c.family, c.pricing_mode, c.tracking,
                   c.gst_pct, c.making_type AS cat_making_type, c.making_value AS cat_making_value,
                   c.wastage_pct AS cat_wastage_pct, l.name AS location_name, v.name AS vendor_name,
                   (SELECT COALESCE(SUM(s.stone_value), 0) FROM stone s WHERE s.item_id = i.id) AS stone_value,
                   (SELECT COALESCE(SUM(s.carat), 0) FROM stone s WHERE s.item_id = i.id) AS stone_carat,
                   (SELECT MIN(s.stone_type) FROM stone s WHERE s.item_id = i.id) AS stone_type
            FROM item i
            JOIN category c ON c.id = i.category_id
            LEFT JOIN location l ON l.id = i.location_id
            LEFT JOIN party v ON v.id = i.vendor_id
            """;

    private final Db db;
    private final RateService rates;
    private final StockLedger ledger;
    private final DocNumbers numbers;
    private final ConfigService config;
    private final AuditService audit;

    public ItemService(Db db, RateService rates, StockLedger ledger, DocNumbers numbers, ConfigService config,
                       AuditService audit) {
        this.db = db;
        this.rates = rates;
        this.ledger = ledger;
        this.numbers = numbers;
        this.config = config;
        this.audit = audit;
    }

    public record ItemFilter(String q, String status, Long categoryId, String family, String metal, String purity,
                             Long locationId, BigDecimal minWt, BigDecimal maxWt, BigDecimal minPrice,
                             BigDecimal maxPrice, String purchaseClass, String stoneType, Integer limit) {}

    // ---------- reading ----------

    public List<Map<String, Object>> search(ItemFilter f) {
        StringBuilder sql = new StringBuilder(SELECT).append(" WHERE 1=1");
        List<Object> args = new ArrayList<>();
        if (f.status() != null && !f.status().equals("ALL")) {
            sql.append(" AND i.status = ?");
            args.add(f.status());
        }
        if (f.categoryId() != null) { sql.append(" AND i.category_id = ?"); args.add(f.categoryId()); }
        if (f.family() != null) { sql.append(" AND c.family = ?"); args.add(f.family()); }
        if (f.metal() != null) { sql.append(" AND i.metal = ?"); args.add(f.metal()); }
        if (f.purity() != null) { sql.append(" AND i.purity_code = ?"); args.add(f.purity()); }
        if (f.locationId() != null) { sql.append(" AND i.location_id = ?"); args.add(f.locationId()); }
        if (f.minWt() != null) { sql.append(" AND i.net_wt >= ?"); args.add(f.minWt()); }
        if (f.maxWt() != null) { sql.append(" AND i.net_wt <= ?"); args.add(f.maxWt()); }
        if (f.stoneType() != null) {
            sql.append(" AND EXISTS (SELECT 1 FROM stone s WHERE s.item_id = i.id AND s.stone_type = ?)");
            args.add(f.stoneType());
        }
        if (f.purchaseClass() != null && CurrentUser.can(Permission.VIEW_PURCHASE_CLASS)) {
            sql.append(" AND i.purchase_class = ?");
            args.add(f.purchaseClass());
        }
        if (f.q() != null && !f.q().isBlank()) {
            String like = "%" + f.q().trim().toLowerCase() + "%";
            sql.append(" AND (LOWER(i.tag_code) LIKE ? OR LOWER(i.name) LIKE ? OR LOWER(COALESCE(i.design_code,'')) LIKE ?"
                    + " OR LOWER(COALESCE(i.huid,'')) LIKE ? OR LOWER(c.name) LIKE ?)");
            for (int k = 0; k < 5; k++) args.add(like);
        }
        sql.append(" ORDER BY i.id DESC");
        List<Map<String, Object>> rows = db.rows(sql.toString(), args.toArray());

        Map<String, BigDecimal> rateMap = todayRates();
        List<Map<String, Object>> out = new ArrayList<>();
        int limit = f.limit() == null ? 500 : f.limit();
        for (Map<String, Object> r : rows) {
            Map<String, Object> item = present(r, rateMap);
            BigDecimal price = (BigDecimal) item.get("price");
            if (f.minPrice() != null && (price == null || price.compareTo(f.minPrice()) < 0)) continue;
            if (f.maxPrice() != null && (price == null || price.compareTo(f.maxPrice()) > 0)) continue;
            out.add(item);
            if (out.size() >= limit) break;
        }
        return out;
    }

    public Map<String, Object> get(long id) {
        Map<String, Object> r = db.one(SELECT + " WHERE i.id = ?", "Item not found", id);
        Map<String, Object> item = present(r, todayRates());
        item.put("stones", db.rows("SELECT * FROM stone WHERE item_id = ? ORDER BY id", id));
        item.put("movements", db.rows("SELECT * FROM stock_movement WHERE item_id = ? ORDER BY id", id));
        return item;
    }

    public Optional<Map<String, Object>> findByCode(String code) {
        String c = code == null ? "" : code.trim();
        return db.opt("SELECT id FROM item WHERE UPPER(tag_code) = UPPER(?) OR UPPER(rfid_epc) = UPPER(?)", c, c)
                .map(r -> get(Rows.id(r)));
    }

    public Map<String, Object> byCode(String code) {
        return findByCode(code).orElseThrow(() -> ApiException.notFound("No item with tag " + code));
    }

    /** Rate per gram for every metal/purity from today's approved set; empty when not approved yet. */
    public Map<String, BigDecimal> todayRates() {
        Map<String, BigDecimal> map = new HashMap<>();
        rates.approvedToday().ifPresent(rs -> {
            for (Map<String, Object> l : db.rows("SELECT * FROM rate_line WHERE rate_set_id = ?", rs.get("id"))) {
                map.put(l.get("metal") + "|" + l.get("purity_code"), (BigDecimal) l.get("rate_per_gram"));
            }
        });
        return map;
    }

    public PriceInput priceInput(Map<String, Object> r, BigDecimal ratePerGram) {
        String makingType = r.get("making_type") != null ? (String) r.get("making_type") : (String) r.get("cat_making_type");
        BigDecimal making = r.get("making_value") != null ? Num.of(r.get("making_value")) : Num.of(r.get("cat_making_value"));
        BigDecimal wastage = r.get("wastage_pct") != null ? Num.of(r.get("wastage_pct")) : Num.of(r.get("cat_wastage_pct"));
        return new PriceInput((String) r.get("pricing_mode"), Num.of(r.get("net_wt")), ratePerGram, makingType, making,
                wastage, Num.of(r.get("stone_value")), Num.of(r.get("fixed_price")), Rows.integer(r.get("quantity"), 1),
                Num.of(r.get("gst_pct")));
    }

    private Map<String, Object> present(Map<String, Object> r, Map<String, BigDecimal> rateMap) {
        Map<String, Object> item = new LinkedHashMap<>(r);
        BigDecimal rate = rateMap.get(r.get("metal") + "|" + r.get("purity_code"));
        boolean fixed = "FIXED".equals(r.get("pricing_mode"));
        if (fixed || rate != null) {
            PriceBreakdown p = PricingEngine.price(priceInput(r, rate == null ? Num.ZERO : rate), Num.ZERO);
            item.put("price", p.total());
            item.put("price_breakdown", p);
        } else {
            item.put("price", null);
        }
        if (!CurrentUser.can(Permission.VIEW_COST)) item.remove("cost_amount");
        if (!CurrentUser.can(Permission.VIEW_PURCHASE_CLASS)) item.remove("purchase_class");
        return item;
    }

    // ---------- writing ----------

    public record NewItemContext(Long vendorId, Long purchaseId, String purchaseClass, String movementType,
                                 String docType, Long docId) {}

    /** Creates one tagged item and posts its receipt movement. Runs inside the caller's transaction. */
    public long create(Map<String, Object> b, NewItemContext ctx) {
        Map<String, Object> cat = db.one("SELECT * FROM category WHERE id = ?", "Choose a category",
                Rows.id(b.get("category_id")));
        String metal = (String) cat.get("metal");
        boolean fixed = "FIXED".equals(cat.get("pricing_mode"));
        String purity = strOrNull(b.get("purity_code"));
        if (!fixed) {
            if (purity == null) throw ApiException.bad("Purity is required for " + cat.get("name") + ".");
            db.one("SELECT id FROM purity WHERE metal = ? AND code = ?", "Purity " + purity + " is not set up for " + metal,
                    metal, purity);
        }

        List<Map<String, Object>> stones = stones(b.get("stones"));
        BigDecimal gross = Num.of(b.get("gross_wt"));
        BigDecimal stoneWt = b.get("stone_wt") == null || str(b.get("stone_wt")).isEmpty()
                ? Num.mul(stones.stream().map(s -> Num.of(s.get("carat"))).reduce(Num.ZERO, BigDecimal::add), CARAT_TO_GRAM)
                : Num.of(b.get("stone_wt"));
        BigDecimal net = b.get("net_wt") == null || str(b.get("net_wt")).isEmpty() ? Num.r(gross.subtract(stoneWt)) : Num.of(b.get("net_wt"));
        if (!fixed) {
            if (!Num.positive(gross) || !Num.positive(net)) throw ApiException.bad("Gross and net weight must be more than zero.");
            if (net.compareTo(gross) > 0) throw ApiException.bad("Net weight cannot be more than gross weight.");
        } else if (!Num.positive(Num.of(b.get("fixed_price")))) {
            throw ApiException.bad("Selling price (MRP) is required for gifting items.");
        }
        int qty = "QUANTITY".equals(cat.get("tracking")) ? Math.max(1, Rows.integer(b.get("quantity"), 1)) : 1;

        String tag = strOrNull(b.get("tag_code"));
        if (tag == null) tag = config.get("tag.prefix", "T") + String.format("%06d", numbers.nextValue("TAG"));
        Long location = Rows.idOrNull(b.get("location_id"));
        if (location == null) location = db.value("SELECT id FROM location WHERE code = 'C1'", Long.class);

        long id = db.insert("""
                INSERT INTO item (tag_code, category_id, name, metal, purity_code, gross_wt, stone_wt, net_wt,
                    making_type, making_value, wastage_pct, fixed_price, quantity, huid, design_code, collection,
                    location_id, status, vendor_id, purchase_id, purchase_class, cost_amount, notes, created_by)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'IN_STOCK', ?,?,?,?,?,?)""",
                tag.toUpperCase(), cat.get("id"), str(b.get("name")).isEmpty() ? cat.get("name") : str(b.get("name")),
                metal, fixed ? null : purity, gross, stoneWt, fixed ? Num.ZERO : net,
                strOrNull(b.get("making_type")), Num.ofNullable(b.get("making_value")), Num.ofNullable(b.get("wastage_pct")),
                fixed ? Num.of(b.get("fixed_price")) : null, qty, strOrNull(b.get("huid")), strOrNull(b.get("design_code")),
                strOrNull(b.get("collection")), location, ctx.vendorId(), ctx.purchaseId(), ctx.purchaseClass(),
                Num.ofNullable(b.get("cost_amount")), strOrNull(b.get("notes")), CurrentUser.usernameOrSystem());

        for (Map<String, Object> s : stones) {
            BigDecimal carat = Num.of(s.get("carat"));
            BigDecimal rate = Num.of(s.get("rate_per_carat"));
            BigDecimal value = s.get("value") == null || str(s.get("value")).isEmpty() ? Num.mul(carat, rate) : Num.of(s.get("value"));
            db.update("""
                    INSERT INTO stone (item_id, stone_type, pieces, carat, rate_per_carat, stone_value, clarity, colour, certificate)
                    VALUES (?,?,?,?,?,?,?,?,?)""", id, str(s.get("stone_type")).isEmpty() ? "DIAMOND" : str(s.get("stone_type")).toUpperCase(),
                    Rows.integer(s.get("pieces"), 1), carat, rate, value, strOrNull(s.get("clarity")),
                    strOrNull(s.get("colour")), strOrNull(s.get("certificate")));
        }
        ledger.post(new StockLedger.Move(id, ctx.movementType(), qty, "IN_STOCK", "IN_STOCK", location,
                ctx.docType(), ctx.docId() == null ? id : ctx.docId(), null));
        audit.log("ITEM_CREATE", "item", tag, cat.get("code") + " " + purity + " net " + net);
        return id;
    }

    /** Opening stock entered directly (not through a purchase). */
    @Transactional
    public Map<String, Object> createOpening(Map<String, Object> b) {
        CurrentUser.require(Permission.ITEM_EDIT);
        long id = create(b, new NewItemContext(Rows.idOrNull(b.get("vendor_id")), null,
                strOrNull(b.get("purchase_class")), "OPENING", "OPENING", null));
        return get(id);
    }

    @Transactional
    public Map<String, Object> update(long id, Map<String, Object> b) {
        CurrentUser.require(Permission.ITEM_EDIT);
        Map<String, Object> item = db.one("SELECT * FROM item WHERE id = ?", "Item not found", id);
        if (!"IN_STOCK".equals(item.get("status"))) throw ApiException.conflict("Only items in stock can be edited.");
        BigDecimal gross = b.containsKey("gross_wt") ? Num.of(b.get("gross_wt")) : Num.of(item.get("gross_wt"));
        BigDecimal stoneWt = b.containsKey("stone_wt") ? Num.of(b.get("stone_wt")) : Num.of(item.get("stone_wt"));
        BigDecimal net = b.containsKey("net_wt") ? Num.of(b.get("net_wt")) : Num.of(item.get("net_wt"));
        if (item.get("metal") != null && net.compareTo(gross) > 0) throw ApiException.bad("Net weight cannot be more than gross weight.");
        db.update("""
                UPDATE item SET name = ?, gross_wt = ?, stone_wt = ?, net_wt = ?, making_type = ?, making_value = ?,
                    wastage_pct = ?, fixed_price = ?, huid = ?, design_code = ?, collection = ?, notes = ?
                WHERE id = ?""",
                b.containsKey("name") ? str(b.get("name")) : item.get("name"), gross, stoneWt, net,
                b.containsKey("making_type") ? strOrNull(b.get("making_type")) : item.get("making_type"),
                b.containsKey("making_value") ? Num.ofNullable(b.get("making_value")) : item.get("making_value"),
                b.containsKey("wastage_pct") ? Num.ofNullable(b.get("wastage_pct")) : item.get("wastage_pct"),
                b.containsKey("fixed_price") ? Num.ofNullable(b.get("fixed_price")) : item.get("fixed_price"),
                b.containsKey("huid") ? strOrNull(b.get("huid")) : item.get("huid"),
                b.containsKey("design_code") ? strOrNull(b.get("design_code")) : item.get("design_code"),
                b.containsKey("collection") ? strOrNull(b.get("collection")) : item.get("collection"),
                b.containsKey("notes") ? strOrNull(b.get("notes")) : item.get("notes"), id);
        audit.log("ITEM_EDIT", "item", item.get("tag_code"),
                "gross " + item.get("gross_wt") + "->" + gross + ", net " + item.get("net_wt") + "->" + net);
        return get(id);
    }

    @Transactional
    public Map<String, Object> transfer(long id, long locationId) {
        CurrentUser.require(Permission.ITEM_EDIT);
        Map<String, Object> loc = db.one("SELECT * FROM location WHERE id = ?", "Location not found", locationId);
        ledger.post(new StockLedger.Move(id, "TRANSFER", 0, "IN_STOCK", "IN_STOCK", locationId, "TRANSFER", null,
                "to " + loc.get("name")));
        return get(id);
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> stones(Object o) {
        if (o == null) return List.of();
        return ((List<Map<String, Object>>) o).stream()
                .filter(s -> Num.positive(Num.of(s.get("carat"))) || Num.positive(Num.of(s.get("value"))))
                .toList();
    }
}
