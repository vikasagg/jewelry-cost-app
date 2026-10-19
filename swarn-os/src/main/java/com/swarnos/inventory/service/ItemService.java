package com.swarnos.inventory.service;

import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import com.swarnos.common.numbering.service.DocumentNumberService;
import com.swarnos.inventory.domain.Item;
import com.swarnos.inventory.domain.ItemCriteria;
import com.swarnos.inventory.domain.ItemListing;
import com.swarnos.inventory.domain.ItemOrigin;
import com.swarnos.inventory.domain.ItemStatus;
import com.swarnos.inventory.domain.ItemWeights;
import com.swarnos.inventory.domain.MovementType;
import com.swarnos.inventory.domain.NewItem;
import com.swarnos.inventory.domain.NewStone;
import com.swarnos.inventory.domain.PriceBreakdown;
import com.swarnos.inventory.domain.PricingEngine;
import com.swarnos.inventory.domain.PurchaseClass;
import com.swarnos.inventory.domain.StatusMismatch;
import com.swarnos.inventory.domain.Stone;
import com.swarnos.inventory.domain.StockMove;
import com.swarnos.inventory.domain.StockMovement;
import com.swarnos.inventory.repository.ItemRepository;
import com.swarnos.inventory.repository.StoneRepository;
import com.swarnos.rates.domain.DailyRates;
import com.swarnos.rates.service.RateService;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.settings.domain.Category;
import com.swarnos.settings.domain.Location;
import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.SettingKeys;
import com.swarnos.settings.domain.Tracking;
import com.swarnos.settings.service.MasterDataService;
import com.swarnos.settings.service.SettingsService;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Item master, tags and live pricing (BRD §3, §4). */
@Service
public class ItemService {
    private static final int DEFAULT_LIMIT = 500;

    private final ItemRepository items;
    private final StoneRepository stones;
    private final StockLedgerService stockLedger;
    private final RateService rates;
    private final MasterDataService masters;
    private final SettingsService settings;
    private final DocumentNumberService numbers;
    private final AuditService audit;

    public ItemService(ItemRepository items, StoneRepository stones, StockLedgerService stockLedger, RateService rates,
                       MasterDataService masters, SettingsService settings, DocumentNumberService numbers, AuditService audit) {
        this.items = items;
        this.stones = stones;
        this.stockLedger = stockLedger;
        this.rates = rates;
        this.masters = masters;
        this.settings = settings;
        this.numbers = numbers;
        this.audit = audit;
    }

    /** An item with its price at today's approved rate (null price when no rate is approved yet). */
    public record PricedItem(ItemListing listing, PriceBreakdown price) {
        public BigDecimal total() {
            return price == null ? null : price.total();
        }
    }

    public record ItemDetail(PricedItem item, List<Stone> stones, List<StockMovement> movements) {}

    public record ItemSearch(ItemCriteria criteria, BigDecimal minPrice, BigDecimal maxPrice, Integer limit) {}

    /** Editable fields; null weights keep the current value, null making/wastage fall back to the category. */
    public record ItemChanges(String name, BigDecimal grossWt, BigDecimal stoneWt, BigDecimal netWt, MakingType makingType,
                              BigDecimal makingValue, BigDecimal wastagePct, BigDecimal fixedPrice, String huid,
                              String designCode, String collection, String notes) {}

    // ---------- queries ----------

    public List<PricedItem> search(ItemSearch q) {
        ItemCriteria c = q.criteria();
        if (c.purchaseClass() != null && !CurrentUser.can(Permission.VIEW_PURCHASE_CLASS)) {
            c = new ItemCriteria(c.text(), c.status(), c.categoryId(), c.family(), c.metal(), c.purity(), c.locationId(),
                    c.minWt(), c.maxWt(), c.stoneType(), null);
        }
        Optional<DailyRates> today = rates.todayRatesIfApproved();
        int limit = q.limit() == null ? DEFAULT_LIMIT : q.limit();
        List<PricedItem> out = new ArrayList<>();
        for (ItemListing listing : items.search(c)) {
            PricedItem p = price(listing, today);
            BigDecimal total = p.total();
            if (q.minPrice() != null && (total == null || total.compareTo(q.minPrice()) < 0)) continue;
            if (q.maxPrice() != null && (total == null || total.compareTo(q.maxPrice()) > 0)) continue;
            out.add(p);
            if (out.size() >= limit) break;
        }
        return out;
    }

    public List<PricedItem> inStock() {
        return search(new ItemSearch(ItemCriteria.inStock(), null, null, Integer.MAX_VALUE));
    }

    public ItemDetail detail(long id) {
        ItemListing listing = listing(id);
        return new ItemDetail(price(listing, rates.todayRatesIfApproved()), stones.findByItem(id), stockLedger.history(id));
    }

    public Optional<ItemDetail> findByCode(String code) {
        return items.findIdByCode(code == null ? "" : code.trim()).map(this::detail);
    }

    public Optional<ItemDetail> findByCodeSuffix(String digits) {
        return items.findIdByCodeSuffix(digits).map(this::detail);
    }

    public ItemDetail requireByCode(String code) {
        return findByCode(code).orElseThrow(() -> BusinessException.notFound("No item with tag " + code));
    }

    public Optional<Long> findIdByCode(String code) {
        return items.findIdByCode(code);
    }

    public ItemListing listing(long id) {
        return items.findListing(id).orElseThrow(() -> BusinessException.notFound("Item not found"));
    }

    public List<ItemListing> listings(Collection<Long> ids) {
        return items.findListings(ids);
    }

    public List<Long> inStockIds(Long locationId, Long categoryId) {
        return items.findInStockIds(locationId, categoryId);
    }

    public List<StatusMismatch> ledgerCheck() {
        return stockLedger.verify();
    }

    // ---------- commands ----------

    /** Creates one tagged item and posts its receipt movement. Runs inside the caller's transaction. */
    public long create(NewItem req, ItemOrigin origin) {
        if (req.categoryId() == null) throw BusinessException.validation("Choose a category.");
        Category category = masters.category(req.categoryId());
        boolean fixed = category.isFixedPrice();
        List<NewStone> stoneLines = req.presentStones();

        ItemWeights weights;
        String purity = null;
        if (fixed) {
            if (!Decimals.isPositive(req.fixedPrice())) throw BusinessException.validation("Selling price (MRP) is required for gifting items.");
            weights = new ItemWeights(Decimals.orZero(req.grossWt()), Decimals.orZero(req.stoneWt()), Decimals.ZERO);
        } else {
            if (req.purityCode() == null || req.purityCode().isBlank()) {
                throw BusinessException.validation("Purity is required for " + category.name() + ".");
            }
            purity = masters.purity(category.metal(), req.purityCode().trim()).code();
            weights = ItemWeights.resolve(req.grossWt(), req.stoneWt(), req.netWt(), stoneLines);
        }
        int quantity = category.tracking() == Tracking.QUANTITY ? Math.max(1, req.quantity() == null ? 1 : req.quantity()) : 1;
        String tag = req.tagCode() != null && !req.tagCode().isBlank() ? req.tagCode().trim().toUpperCase()
                : numbers.nextTagCode(settings.text(SettingKeys.TAG_PREFIX, "T"));
        long location = req.locationId() != null ? masters.location(req.locationId()).id() : masters.defaultCounter().id();

        Item item = new Item(0, tag, null, category.id(), req.name() == null || req.name().isBlank() ? category.name() : req.name().trim(),
                category.metal(), purity, weights.gross(), weights.stone(), weights.net(), req.makingType(),
                Decimals.roundOrNull(req.makingValue()), Decimals.roundOrNull(req.wastagePct()),
                fixed ? Decimals.round(req.fixedPrice()) : null, quantity, blank(req.huid()), blank(req.designCode()),
                blank(req.collection()), location, ItemStatus.IN_STOCK, origin.vendorId(), origin.purchaseId(),
                origin.purchaseClass(), Decimals.roundOrNull(req.costAmount()), blank(req.notes()), CurrentUser.usernameOrSystem(), null);
        long id = items.insert(item);
        for (NewStone s : stoneLines) {
            stones.insert(new Stone(0, id, s.type(), s.pieces() == null ? 1 : s.pieces(), Decimals.orZero(s.carat()),
                    Decimals.orZero(s.ratePerCarat()), s.resolvedValue(), blank(s.clarity()), blank(s.colour()), blank(s.certificate())));
        }
        stockLedger.post(new StockMove(id, origin.movementType(), quantity, Set.of(ItemStatus.IN_STOCK), ItemStatus.IN_STOCK,
                location, origin.docType(), origin.docId() == null ? id : origin.docId(), null));
        audit.record("ITEM_CREATE", "item", tag, category.code() + " " + purity + " net " + weights.net());
        return id;
    }

    /** Opening stock entered directly (not through a purchase). */
    @Transactional
    public ItemDetail createOpening(NewItem req, Long vendorId, PurchaseClass purchaseClass) {
        CurrentUser.require(Permission.ITEM_EDIT);
        return detail(create(req, ItemOrigin.opening(vendorId, purchaseClass)));
    }

    @Transactional
    public ItemDetail update(long id, ItemChanges c) {
        CurrentUser.require(Permission.ITEM_EDIT);
        Item item = items.findById(id).orElseThrow(() -> BusinessException.notFound("Item not found"));
        if (item.status() != ItemStatus.IN_STOCK) throw BusinessException.conflict("Only items in stock can be edited.");
        BigDecimal gross = c.grossWt() == null ? item.grossWt() : Decimals.round(c.grossWt());
        BigDecimal stone = c.stoneWt() == null ? item.stoneWt() : Decimals.round(c.stoneWt());
        BigDecimal net = c.netWt() == null ? item.netWt() : Decimals.round(c.netWt());
        if (item.metal() != null && net.compareTo(gross) > 0) throw BusinessException.validation("Net weight cannot be more than gross weight.");
        items.updateDetails(new Item(id, item.tagCode(), item.rfidEpc(), item.categoryId(),
                c.name() == null || c.name().isBlank() ? item.name() : c.name().trim(), item.metal(), item.purityCode(), gross, stone,
                net, c.makingType(), Decimals.roundOrNull(c.makingValue()), Decimals.roundOrNull(c.wastagePct()),
                item.metal() == null && c.fixedPrice() != null ? Decimals.round(c.fixedPrice()) : item.fixedPrice(), item.quantity(),
                blank(c.huid()), blank(c.designCode()), blank(c.collection()), item.locationId(), item.status(), item.vendorId(),
                item.purchaseId(), item.purchaseClass(), item.costAmount(), blank(c.notes()), item.createdBy(), item.createdAt()));
        audit.record("ITEM_EDIT", "item", item.tagCode(), "gross " + item.grossWt() + "->" + gross + ", net " + item.netWt() + "->" + net);
        return detail(id);
    }

    @Transactional
    public ItemDetail transfer(long id, long locationId) {
        CurrentUser.require(Permission.ITEM_EDIT);
        Location to = masters.location(locationId);
        stockLedger.post(new StockMove(id, MovementType.TRANSFER, 0, Set.of(ItemStatus.IN_STOCK), ItemStatus.IN_STOCK, to.id(),
                "TRANSFER", null, "to " + to.name()));
        return detail(id);
    }

    public void changePurchaseClass(long purchaseId, PurchaseClass cls) {
        items.updatePurchaseClass(purchaseId, cls);
    }

    private PricedItem price(ItemListing listing, Optional<DailyRates> today) {
        return new PricedItem(listing, PricingEngine.priceAt(listing, today).orElse(null));
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
