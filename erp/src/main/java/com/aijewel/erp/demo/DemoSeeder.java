package com.aijewel.erp.demo;

import com.aijewel.erp.common.AppProperties;
import com.aijewel.erp.common.Db;
import com.aijewel.erp.common.Rows;
import com.aijewel.erp.ledger.LedgerService;
import com.aijewel.erp.parties.PartyService;
import com.aijewel.erp.purchase.PurchaseService;
import com.aijewel.erp.rates.RateService;
import com.aijewel.erp.repair.RepairService;
import com.aijewel.erp.sales.SaleService;
import com.aijewel.erp.tenant.TenantContext;
import com.aijewel.erp.tenant.TenantProvisioner;
import com.aijewel.erp.tenant.TenantRegistry;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * Creates the "demo" shop on first start with users for every role, today's
 * approved rate, parties, stock bought in every purchase mode, one bill and
 * one repair job, so every screen has something to show.
 */
@Component
@Order(2)
public class DemoSeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(DemoSeeder.class);
    public static final String CODE = "demo";
    public static final String PASSWORD = "demo123";

    private final AppProperties props;
    private final TenantRegistry registry;
    private final TenantProvisioner provisioner;
    private final Db db;
    private final RateService rates;
    private final PartyService parties;
    private final PurchaseService purchases;
    private final SaleService sales;
    private final RepairService repairs;
    private final LedgerService ledgers;

    public DemoSeeder(AppProperties props, TenantRegistry registry, TenantProvisioner provisioner, Db db, RateService rates,
                      PartyService parties, PurchaseService purchases, SaleService sales, RepairService repairs,
                      LedgerService ledgers) {
        this.props = props;
        this.registry = registry;
        this.provisioner = provisioner;
        this.db = db;
        this.rates = rates;
        this.parties = parties;
        this.purchases = purchases;
        this.sales = sales;
        this.repairs = repairs;
        this.ledgers = ledgers;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (props.demo() == null || !props.demo().enabled() || registry.find(CODE).isPresent()) return;
        provisioner.create(new TenantProvisioner.NewTenant(CODE, "Demo Jewellers",
                props.demo().storageMode() == null ? "LOCAL" : props.demo().storageMode(), "owner", "Owner", PASSWORD));
        TenantContext.call(CODE, () -> {
            seed();
            return null;
        });
        log.info("Demo shop ready: shop code '{}', users owner / manager / sales / accounts / stock, password '{}'", CODE, PASSWORD);
    }

    /** Also used to refresh the demo rate on later days (Rates screen still needs a person to approve). */
    void seed() {
        BCryptPasswordEncoder enc = new BCryptPasswordEncoder();
        String hash = enc.encode(PASSWORD);
        for (String[] u : new String[][] {{"manager", "Store Manager", "MANAGER"}, {"sales", "Salesperson", "SALES"},
                {"accounts", "Accountant", "ACCOUNTANT"}, {"stock", "Stock Keeper", "STOCK"}}) {
            db.update("INSERT INTO app_user (username, full_name, password_hash, role) VALUES (?,?,?,?)", u[0], u[1], hash, u[2]);
        }
        db.update("UPDATE app_config SET config_value = ? WHERE config_key = 'shop.address'", "12 Johari Bazaar, Jaipur, Rajasthan");
        db.update("UPDATE app_config SET config_value = ? WHERE config_key = 'shop.phone'", "+91 98290 00000");
        db.update("UPDATE app_config SET config_value = ? WHERE config_key = 'shop.gstin'", "08ABCDE1234F1Z5");

        for (Object[] o : new Object[][] {{"CASH", "500000"}, {"BANK", "3000000"}, {"GOLD", "50"}, {"SILVER", "1000"}}) {
            ledgers.post((String) o[0], null, "OPENING", 0, bd((String) o[1]), BigDecimal.ZERO, "Opening balance");
        }
        Map<String, Object> rs = rates.propose("MANUAL", bd("7500"), bd("92"), bd("3100"), "Manual entry", "Demo morning rate");
        rates.approve(Rows.id(rs));

        long ganesh = party("VENDOR", "Shree Ganesh Ornaments", "9829011111", "08AAACG1234K1Z2");
        long kalash = party("VENDOR", "Kalash Diamonds", "9829022222", "27AABCK5678L1Z9");
        long silverCraft = party("VENDOR", "Silver Craft Rajkot", "9825033333", null);
        long platinumHouse = party("VENDOR", "Platinum House", "9820044444", "27AADCP4321M1Z1");
        long giftCo = party("VENDOR", "Gift Gallery Wholesale", "9829055555", "08AAFCG9876N1Z3");
        long anita = party("CUSTOMER", "Anita Sharma", "9876500001", null);
        long rahul = party("CUSTOMER", "Rahul Verma", "9876500002", null);
        party("CUSTOMER", "Priya Gupta", "9876500003", null);
        long walkIn = party("CUSTOMER", "Mohan Lal (walk-in seller)", "9876500004", null);
        party("KARIGAR", "Ramesh Karigar", "9829066666", null);

        Map<String, Long> cat = new HashMap<>();
        db.rows("SELECT id, code FROM category").forEach(r -> cat.put((String) r.get("code"), Rows.id(r)));

        // 1. Gold jewellery: bank transfer with a GST invoice -> Seen.
        List<Map<String, Object>> gold = new ArrayList<>();
        Object[][] goldItems = {
                {"GCH", "Rope Chain", "22K", "12.450", "0", "92000"}, {"GCH", "Box Chain", "22K", "8.320", "0", "61500"},
                {"GCH", "Singapore Chain", "18K", "6.100", "0", "35000"}, {"GCH", "Heavy Curb Chain", "22K", "24.800", "0", "183000"},
                {"LGR", "Floral Ladies Ring", "22K", "3.250", "0.050", "24500"}, {"LGR", "Solitaire-style Ring", "18K", "2.900", "0", "16800"},
                {"GGR", "Gents Signet Ring", "22K", "7.600", "0", "56000"}, {"GE", "Jhumka Earrings", "22K", "9.150", "0.200", "68000"},
                {"GE", "Stud Earrings", "18K", "2.400", "0", "14000"}, {"GBG", "Plain Bangle Pair", "22K", "22.300", "0", "163000"},
                {"GBG", "Kada", "22K", "18.750", "0", "137000"}, {"GNS", "Temple Necklace Set", "22K", "38.600", "1.200", "285000"},
                {"GPD", "Om Pendant", "22K", "3.800", "0", "28000"}, {"GPS", "Peacock Pendant Set", "22K", "14.200", "0.350", "105000"},
                {"GMS", "Mangalsutra", "22K", "11.900", "0.400", "87000"}, {"GCH", "Kids Chain", "14K", "4.200", "0", "18500"},
                {"GE", "Hoop Earrings", "9K", "3.100", "0", "8200"}};
        for (Object[] g : goldItems) {
            gold.add(line(cat.get((String) g[0]), (String) g[1], (String) g[2], (String) g[3], (String) g[4], (String) g[5], null));
        }
        purchase(ganesh, "FINISHED", "GI/2026/0912", gold, Map.of("bank", "1400000", "bank_ref", "NEFT UTR 4455"));

        // 2. Diamond jewellery with stone details, bank, Seen.
        List<Map<String, Object>> dia = new ArrayList<>();
        dia.add(diamond(cat.get("DRG"), "Diamond Solitaire Ring", "18K", "3.200", "0.30", "70000", "48000"));
        dia.add(diamond(cat.get("DRG"), "Diamond Cluster Ring", "18K", "4.100", "0.45", "65000", "62000"));
        dia.add(diamond(cat.get("DE"), "Diamond Studs", "18K", "2.600", "0.20", "70000", "36000"));
        dia.add(diamond(cat.get("DE"), "Diamond Drop Earrings", "18K", "5.400", "0.80", "75000", "112000"));
        dia.add(diamond(cat.get("DPD"), "Heart Diamond Pendant", "18K", "1.900", "0.15", "70000", "24000"));
        dia.add(diamond(cat.get("DPD"), "Diamond Pendant (small)", "14K", "1.200", "0.08", "65000", "12500"));
        dia.add(diamond(cat.get("DNS"), "Diamond Necklace Set", "18K", "28.500", "3.50", "80000", "560000"));
        dia.add(diamond(cat.get("DBG"), "Diamond Bangle", "18K", "16.800", "1.20", "75000", "205000"));
        dia.forEach(l -> l.put("location_id", counter2()));
        purchase(kalash, "FINISHED", "KD/26-27/221", dia, Map.of("bank", "1059500", "bank_ref", "RTGS 99812"));

        // 3. Silver ornaments bought for cash without GST -> Unseen.
        List<Map<String, Object>> silver = new ArrayList<>();
        Object[][] silverItems = {
                {"SAN", "Ghungroo Payal Pair", "925", "48.500", "5600"}, {"SAN", "Light Payal Pair", "925", "28.200", "3300"},
                {"SAN", "Bridal Payal Pair", "925", "95.000", "10800"}, {"STR", "Toe Ring Pair", "925", "6.400", "800"},
                {"SBR", "Silver Bracelet", "925", "22.000", "2600"}, {"SCN", "Lakshmi Silver Coin 10g", "999", "10.000", "1000"},
                {"SCN", "Silver Coin 20g", "999", "20.000", "1950"}, {"SUT", "Silver Glass", "999", "65.000", "6400"}};
        for (Object[] s : silverItems) {
            silver.add(line(cat.get((String) s[0]), (String) s[1], (String) s[2], (String) s[3], "0", (String) s[4], null));
        }
        silver.forEach(l -> l.put("location_id", counter2()));
        purchase(silverCraft, "FINISHED", null, silver, Map.of("cash", "32450"));

        // 4. Old gold bought from a walk-in seller for cash (a "treat" purchase) -> fine gold in the metal book.
        purchases.create(Map.of("party_id", walkIn, "purchase_kind", "OLD_METAL", "lines", List.of(
                Map.of("description", "Old broken chain", "metal", "GOLD", "purity_code", "22K", "gross_wt", "15.000", "net_wt", "14.800")),
                "payment", Map.of("cash", "99000"), "notes", "Purity tested on karat meter"));

        // 5. Platinum bought partly against gold and partly by bank -> mixed settlement.
        List<Map<String, Object>> pt = new ArrayList<>();
        pt.add(line(cat.get("PTR"), "Platinum Band", "950", "6.200", "0", "21500", null));
        pt.add(line(cat.get("PTC"), "Platinum Chain", "950", "10.500", "0", "36000", null));
        pt.forEach(l -> l.put("location_id", vault()));
        purchase(platinumHouse, "FINISHED", "PH/1187", pt, Map.of("gold_fine", "5.000", "bank", "20145"));

        // 6. Gifting articles with MRP, on credit.
        List<Map<String, Object>> gifts = new ArrayList<>();
        gifts.add(gift(cat.get("GFT"), "Silver-plated Ganesh Idol", "1450", "900", 4));
        gifts.add(gift(cat.get("GFT"), "Brass Diya Set", "650", "380", 6));
        gifts.add(gift(cat.get("WTC"), "Ladies Watch", "4999", "3200", 1));
        purchase(giftCo, "FINISHED", "GG/7781", gifts, Map.of());

        // 7. A bill with an old-gold exchange and split payment.
        String chainTag = db.value("SELECT tag_code FROM item WHERE name = 'Box Chain'", String.class);
        sales.create(Map.of("customer_id", anita,
                "lines", List.of(Map.of("tag_code", chainTag)),
                "exchange", List.of(Map.of("description", "Old earrings", "metal", "GOLD", "purity_code", "22K",
                        "gross_wt", "4.000", "net_wt", "3.900")),
                "payments", List.of(Map.of("mode", "UPI", "amount", "30000", "reference", "UPI 1234"),
                        Map.of("mode", "CASH", "amount", sale1Balance(chainTag, anita)))));

        // 8. A repair job at the counter.
        repairs.intake(Map.of("customer_id", rahul, "description", "Gents ring - resize and polish", "metal", "GOLD",
                "purity_code", "22K", "weight_in", "6.850", "item_condition", "Minor scratches", "repair_type", "Resize",
                "estimate", "800", "promised_date", java.time.LocalDate.now().plusDays(3).toString(), "advance", "300"));
    }

    private String sale1Balance(String tag, long customer) {
        Map<String, Object> q = sales.preview(Map.of("customer_id", customer, "lines", List.of(Map.of("tag_code", tag)),
                "exchange", List.of(Map.of("metal", "GOLD", "purity_code", "22K", "gross_wt", "4.000", "net_wt", "3.900"))));
        return ((BigDecimal) q.get("net_payable")).subtract(new BigDecimal("30000")).toPlainString();
    }

    private long counter2() {
        return db.value("SELECT id FROM location WHERE code = 'C2'", Long.class);
    }

    private long vault() {
        return db.value("SELECT id FROM location WHERE code = 'VAULT'", Long.class);
    }

    private long party(String type, String name, String phone, String gstin) {
        Map<String, Object> b = new HashMap<>();
        b.put("party_type", type);
        b.put("name", name);
        b.put("phone", phone);
        b.put("gstin", gstin);
        b.put("address", "Jaipur");
        return Rows.id(parties.save(b));
    }

    private void purchase(long party, String kind, String gstInvoice, List<Map<String, Object>> lines, Map<String, Object> pay) {
        Map<String, Object> b = new HashMap<>();
        b.put("party_id", party);
        b.put("purchase_kind", kind);
        b.put("gst_invoice_no", gstInvoice);
        b.put("lines", lines);
        Map<String, Object> payment = new HashMap<>(pay);
        b.put("payment", payment);
        // Pay the exact value when the demo amount is a round figure close to it.
        Map<String, Object> created = purchases.create(b);
        if (!pay.isEmpty()) log.debug("Demo purchase {} balance {}", created.get("purchase_no"), created.get("balance_due"));
    }

    private static Map<String, Object> line(long categoryId, String name, String purity, String gross, String stoneWt,
                                            String cost, List<Map<String, Object>> stones) {
        Map<String, Object> m = new HashMap<>();
        m.put("category_id", categoryId);
        m.put("name", name);
        m.put("purity_code", purity);
        m.put("gross_wt", gross);
        m.put("stone_wt", stoneWt);
        m.put("cost_amount", cost);
        m.put("huid", purity.endsWith("K") ? "HU" + Math.abs((name + gross).hashCode() % 10000) : null);
        if (stones != null) m.put("stones", stones);
        return m;
    }

    private static Map<String, Object> diamond(long categoryId, String name, String purity, String gross, String carat,
                                               String ratePerCarat, String cost) {
        BigDecimal stoneGrams = new BigDecimal(carat).multiply(new BigDecimal("0.2"));
        Map<String, Object> m = line(categoryId, name, purity, gross, stoneGrams.toPlainString(), cost,
                List.of(Map.of("stone_type", "DIAMOND", "pieces", 1, "carat", carat, "rate_per_carat", ratePerCarat,
                        "clarity", "VS1", "colour", "F", "certificate", "IGI-" + Math.abs(name.hashCode() % 100000))));
        return m;
    }

    private static Map<String, Object> gift(long categoryId, String name, String mrp, String cost, int qty) {
        Map<String, Object> m = new HashMap<>();
        m.put("category_id", categoryId);
        m.put("name", name);
        m.put("fixed_price", mrp);
        m.put("quantity", qty);
        m.put("cost_amount", new BigDecimal(cost).multiply(BigDecimal.valueOf(qty)).toPlainString());
        return m;
    }

    private static BigDecimal bd(String s) {
        return new BigDecimal(s);
    }
}
