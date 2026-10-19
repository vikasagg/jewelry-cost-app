package com.swarnos.demo;

import com.swarnos.accounting.domain.Book;
import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.accounting.service.LedgerService;
import com.swarnos.common.config.AppProperties;
import com.swarnos.identity.service.UserService;
import com.swarnos.inventory.domain.NewItem;
import com.swarnos.inventory.domain.NewStone;
import com.swarnos.parties.domain.PartyDetails;
import com.swarnos.parties.domain.PartyType;
import com.swarnos.parties.service.PartyService;
import com.swarnos.purchase.domain.OldMetalLine;
import com.swarnos.purchase.domain.PaymentLegs;
import com.swarnos.purchase.domain.PurchaseKind;
import com.swarnos.purchase.service.PurchaseCommand;
import com.swarnos.purchase.service.PurchaseService;
import com.swarnos.rates.domain.BaseRates;
import com.swarnos.rates.service.RateService;
import com.swarnos.repair.service.RepairService;
import com.swarnos.sales.domain.BillQuote;
import com.swarnos.sales.service.SaleCommand;
import com.swarnos.sales.service.SaleService;
import com.swarnos.security.Role;
import com.swarnos.settings.domain.Category;
import com.swarnos.settings.domain.Location;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.SettingKeys;
import com.swarnos.settings.service.MasterDataService;
import com.swarnos.settings.service.SettingsService;
import com.swarnos.tenant.domain.StorageMode;
import com.swarnos.tenant.infrastructure.TenantContext;
import com.swarnos.tenant.service.TenantProvisioningService;
import com.swarnos.tenant.service.TenantService;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * Creates the "demo" shop on first start through the normal services: users for
 * every role, opening balances, today's approved rate, parties, stock bought in
 * every purchase mode, one bill with an exchange and one repair job.
 */
@Component
@Order(2)
public class DemoSeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(DemoSeeder.class);
    public static final String CODE = "demo";
    public static final String PASSWORD = "demo123";

    private final AppProperties props;
    private final TenantService tenants;
    private final TenantProvisioningService provisioning;
    private final UserService users;
    private final SettingsService settings;
    private final MasterDataService masters;
    private final LedgerService ledger;
    private final RateService rates;
    private final PartyService parties;
    private final PurchaseService purchases;
    private final SaleService sales;
    private final RepairService repairs;

    public DemoSeeder(AppProperties props, TenantService tenants, TenantProvisioningService provisioning, UserService users,
                      SettingsService settings, MasterDataService masters, LedgerService ledger, RateService rates,
                      PartyService parties, PurchaseService purchases, SaleService sales, RepairService repairs) {
        this.props = props;
        this.tenants = tenants;
        this.provisioning = provisioning;
        this.users = users;
        this.settings = settings;
        this.masters = masters;
        this.ledger = ledger;
        this.rates = rates;
        this.parties = parties;
        this.purchases = purchases;
        this.sales = sales;
        this.repairs = repairs;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (props.demo() == null || !props.demo().enabled() || tenants.find(CODE).isPresent()) return;
        StorageMode mode = props.demo().storageMode() == null ? StorageMode.LOCAL : StorageMode.valueOf(props.demo().storageMode());
        provisioning.create(new TenantProvisioningService.NewShop(CODE, "Demo Jewellers", mode, "owner", "Owner", PASSWORD));
        TenantContext.run(CODE, this::seed);
        log.info("Demo shop ready: shop code '{}', users owner / manager / sales / accounts / stock, password '{}'", CODE, PASSWORD);
    }

    private void seed() {
        users.create(new UserService.NewUser("manager", "Store Manager", Role.MANAGER, PASSWORD));
        users.create(new UserService.NewUser("sales", "Salesperson", Role.SALES, PASSWORD));
        users.create(new UserService.NewUser("accounts", "Accountant", Role.ACCOUNTANT, PASSWORD));
        users.create(new UserService.NewUser("stock", "Stock Keeper", Role.STOCK, PASSWORD));
        settings.write(SettingKeys.SHOP_ADDRESS, "12 Johari Bazaar, Jaipur, Rajasthan");
        settings.write(SettingKeys.SHOP_PHONE, "+91 98290 00000");
        settings.write(SettingKeys.SHOP_GSTIN, "08ABCDE1234F1Z5");

        ledger.postOpeningUnchecked(Book.CASH, bd("500000"));
        ledger.postOpeningUnchecked(Book.BANK, bd("3000000"));
        ledger.postOpeningUnchecked(Book.GOLD, bd("50"));
        ledger.postOpeningUnchecked(Book.SILVER, bd("1000"));
        rates.enterManual(new BaseRates(bd("7500"), bd("92"), bd("3100")), true, "Demo morning rate");

        long ganesh = party(PartyType.VENDOR, "Shree Ganesh Ornaments", "9829011111", "08AAACG1234K1Z2");
        long kalash = party(PartyType.VENDOR, "Kalash Diamonds", "9829022222", "27AABCK5678L1Z9");
        long silverCraft = party(PartyType.VENDOR, "Silver Craft Rajkot", "9825033333", null);
        long platinumHouse = party(PartyType.VENDOR, "Platinum House", "9820044444", "27AADCP4321M1Z1");
        long giftCo = party(PartyType.VENDOR, "Gift Gallery Wholesale", "9829055555", "08AAFCG9876N1Z3");
        long anita = party(PartyType.CUSTOMER, "Anita Sharma", "9876500001", null);
        long rahul = party(PartyType.CUSTOMER, "Rahul Verma", "9876500002", null);
        party(PartyType.CUSTOMER, "Priya Gupta", "9876500003", null);
        long walkIn = party(PartyType.CUSTOMER, "Mohan Lal (walk-in seller)", "9876500004", null);
        party(PartyType.KARIGAR, "Ramesh Karigar", "9829066666", null);

        Map<String, Long> cat = masters.activeCategories().stream().collect(Collectors.toMap(Category::code, Category::id));
        Map<String, Long> loc = masters.locations().stream().collect(Collectors.toMap(Location::code, Location::id));

        // 1. Gold jewellery: bank transfer with a GST invoice -> Seen.
        List<NewItem> gold = new ArrayList<>();
        for (String[] g : new String[][] {
                {"GCH", "Rope Chain", "22K", "12.450", "0", "92000"}, {"GCH", "Box Chain", "22K", "8.320", "0", "61500"},
                {"GCH", "Singapore Chain", "18K", "6.100", "0", "35000"}, {"GCH", "Heavy Curb Chain", "22K", "24.800", "0", "183000"},
                {"LGR", "Floral Ladies Ring", "22K", "3.250", "0.050", "24500"}, {"LGR", "Solitaire-style Ring", "18K", "2.900", "0", "16800"},
                {"GGR", "Gents Signet Ring", "22K", "7.600", "0", "56000"}, {"GE", "Jhumka Earrings", "22K", "9.150", "0.200", "68000"},
                {"GE", "Stud Earrings", "18K", "2.400", "0", "14000"}, {"GBG", "Plain Bangle Pair", "22K", "22.300", "0", "163000"},
                {"GBG", "Kada", "22K", "18.750", "0", "137000"}, {"GNS", "Temple Necklace Set", "22K", "38.600", "1.200", "285000"},
                {"GPD", "Om Pendant", "22K", "3.800", "0", "28000"}, {"GPS", "Peacock Pendant Set", "22K", "14.200", "0.350", "105000"},
                {"GMS", "Mangalsutra", "22K", "11.900", "0.400", "87000"}, {"GCH", "Kids Chain", "14K", "4.200", "0", "18500"},
                {"GE", "Hoop Earrings", "9K", "3.100", "0", "8200"}}) {
            gold.add(metalItem(cat.get(g[0]), g[1], g[2], g[3], g[4], g[5], loc.get("C1"), List.of()));
        }
        buyItems(ganesh, "GI/2026/0912", gold, legs("0", "1400000", "NEFT UTR 4455", "0"));

        // 2. Diamond jewellery with stone details on counter 2, bank, Seen.
        List<NewItem> diamonds = new ArrayList<>();
        for (String[] d : new String[][] {
                {"DRG", "Diamond Solitaire Ring", "3.200", "0.30", "70000", "48000"},
                {"DRG", "Diamond Cluster Ring", "4.100", "0.45", "65000", "62000"},
                {"DE", "Diamond Studs", "2.600", "0.20", "70000", "36000"},
                {"DE", "Diamond Drop Earrings", "5.400", "0.80", "75000", "112000"},
                {"DPD", "Heart Diamond Pendant", "1.900", "0.15", "70000", "24000"},
                {"DNS", "Diamond Necklace Set", "28.500", "3.50", "80000", "560000"},
                {"DBG", "Diamond Bangle", "16.800", "1.20", "75000", "205000"}}) {
            NewStone stone = new NewStone("DIAMOND", 1, bd(d[3]), bd(d[4]), null, "VS1", "F", "IGI-" + Math.abs(d[1].hashCode() % 100000));
            diamonds.add(metalItem(cat.get(d[0]), d[1], "18K", d[2], null, d[5], loc.get("C2"), List.of(stone)));
        }
        NewStone small = new NewStone("DIAMOND", 1, bd("0.08"), bd("65000"), null, "SI1", "G", null);
        diamonds.add(metalItem(cat.get("DPD"), "Diamond Pendant (small)", "14K", "1.200", null, "12500", loc.get("C2"), List.of(small)));
        buyItems(kalash, "KD/26-27/221", diamonds, legs("0", "1059500", "RTGS 99812", "0"));

        // 3. Silver ornaments bought for cash without GST -> Unseen.
        List<NewItem> silver = new ArrayList<>();
        for (String[] s : new String[][] {
                {"SAN", "Ghungroo Payal Pair", "925", "48.500", "5600"}, {"SAN", "Light Payal Pair", "925", "28.200", "3300"},
                {"SAN", "Bridal Payal Pair", "925", "95.000", "10800"}, {"STR", "Toe Ring Pair", "925", "6.400", "800"},
                {"SBR", "Silver Bracelet", "925", "22.000", "2600"}, {"SCN", "Lakshmi Silver Coin 10g", "999", "10.000", "1000"},
                {"SCN", "Silver Coin 20g", "999", "20.000", "1950"}, {"SUT", "Silver Glass", "999", "65.000", "6400"}}) {
            silver.add(metalItem(cat.get(s[0]), s[1], s[2], s[3], "0", s[4], loc.get("C2"), List.of()));
        }
        buyItems(silverCraft, null, silver, legs("32450", "0", null, "0"));

        // 4. Old gold bought from a walk-in seller for cash (a "treat" purchase) -> fine gold in the metal book.
        purchases.create(new PurchaseCommand(walkIn, PurchaseKind.OLD_METAL, null, null, null, "Purity tested on karat meter",
                List.of(), List.of(new OldMetalLine("Old broken chain", Metal.GOLD, "22K", bd("15.000"), bd("14.800"), null, null)),
                legs("99000", "0", null, "0")));

        // 5. Platinum bought partly against fine gold and partly by bank -> mixed settlement.
        List<NewItem> platinum = List.of(
                metalItem(cat.get("PTR"), "Platinum Band", "950", "6.200", "0", "21500", loc.get("VAULT"), List.of()),
                metalItem(cat.get("PTC"), "Platinum Chain", "950", "10.500", "0", "36000", loc.get("VAULT"), List.of()));
        buyItems(platinumHouse, "PH/1187", platinum, legs("0", "20145", null, "5.000"));

        // 6. Gifting articles with MRP, on credit.
        buyItems(giftCo, "GG/7781", List.of(
                gift(cat.get("GFT"), "Silver-plated Ganesh Idol", "1450", "900", 4, loc.get("C2")),
                gift(cat.get("GFT"), "Brass Diya Set", "650", "380", 6, loc.get("C2")),
                gift(cat.get("WTC"), "Ladies Watch", "4999", "3200", 1, loc.get("C2"))), PaymentLegs.none());

        // 7. A bill with an old-gold exchange and a split payment.
        SaleCommand.Exchange oldEarrings = new SaleCommand.Exchange("Old earrings", Metal.GOLD, "22K", bd("4.000"), bd("3.900"), null);
        SaleCommand draft = new SaleCommand(anita, null, List.of(new SaleCommand.Line(null, "T000002", null)), List.of(oldEarrings), List.of());
        BillQuote quote = sales.quote(draft);
        BigDecimal upi = bd("30000");
        sales.create(new SaleCommand(anita, null, draft.lines(), draft.exchange(), List.of(
                new SaleCommand.PaymentLeg(PaymentMode.UPI, upi, "UPI 1234"),
                new SaleCommand.PaymentLeg(PaymentMode.CASH, quote.netPayable().subtract(upi), null))));

        // 8. A repair job at the counter.
        repairs.intake(new RepairService.Intake(rahul, "Gents ring - resize and polish", Metal.GOLD, "22K", bd("6.850"),
                "Minor scratches", "Resize", bd("800"), LocalDate.now().plusDays(3), bd("300"), PaymentMode.CASH));
    }

    private long party(PartyType type, String name, String phone, String gstin) {
        return parties.create(new PartyDetails(type, name, phone, null, "Jaipur", gstin, null, null, null, null, null)).id();
    }

    private void buyItems(long vendor, String gstInvoice, List<NewItem> lines, PaymentLegs legs) {
        purchases.create(new PurchaseCommand(vendor, PurchaseKind.FINISHED, gstInvoice, null, null, null, lines, List.of(), legs));
    }

    private static NewItem metalItem(long categoryId, String name, String purity, String gross, String stoneWt, String cost,
                                     long location, List<NewStone> stones) {
        String huid = purity.endsWith("K") ? "HU" + Math.abs((name + gross).hashCode() % 10000) : null;
        return new NewItem(categoryId, null, name, purity, bd(gross), stoneWt == null ? null : bd(stoneWt), null, null, null, null,
                null, null, huid, null, null, location, bd(cost), null, stones);
    }

    private static NewItem gift(long categoryId, String name, String mrp, String unitCost, int qty, long location) {
        return new NewItem(categoryId, null, name, null, null, null, null, null, null, null, bd(mrp), qty, null, null, null, location,
                bd(unitCost).multiply(BigDecimal.valueOf(qty)), null, List.of());
    }

    private static PaymentLegs legs(String cash, String bank, String bankRef, String goldFine) {
        return new PaymentLegs(bd(cash), bd(bank), PaymentMode.BANK, bankRef, bd(goldFine), null);
    }

    private static BigDecimal bd(String s) {
        return new BigDecimal(s);
    }
}
