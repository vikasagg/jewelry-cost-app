package com.swarnos.inventory.api;

import com.swarnos.inventory.api.dto.ItemRequest;
import com.swarnos.inventory.api.dto.ItemResponse;
import com.swarnos.inventory.api.dto.ItemUpdateRequest;
import com.swarnos.inventory.domain.ItemCriteria;
import com.swarnos.inventory.domain.ItemStatus;
import com.swarnos.inventory.domain.PurchaseClass;
import com.swarnos.inventory.domain.StatusMismatch;
import com.swarnos.inventory.service.ItemService;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.ProductFamily;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/items")
public class ItemController {
    private final ItemService items;

    public ItemController(ItemService items) {
        this.items = items;
    }

    /** Stock search; status defaults to IN_STOCK, "ALL" for every status. Price filters use today's rate. */
    @GetMapping
    public List<ItemResponse> search(@RequestParam(required = false) String q,
                                     @RequestParam(defaultValue = "IN_STOCK") String status,
                                     @RequestParam(name = "category_id", required = false) Long categoryId,
                                     @RequestParam(required = false) ProductFamily family,
                                     @RequestParam(required = false) Metal metal,
                                     @RequestParam(required = false) String purity,
                                     @RequestParam(name = "location_id", required = false) Long locationId,
                                     @RequestParam(name = "min_wt", required = false) BigDecimal minWt,
                                     @RequestParam(name = "max_wt", required = false) BigDecimal maxWt,
                                     @RequestParam(name = "min_price", required = false) BigDecimal minPrice,
                                     @RequestParam(name = "max_price", required = false) BigDecimal maxPrice,
                                     @RequestParam(name = "purchase_class", required = false) PurchaseClass purchaseClass,
                                     @RequestParam(name = "stone_type", required = false) String stoneType,
                                     @RequestParam(required = false) Integer limit) {
        ItemStatus st = "ALL".equalsIgnoreCase(status) ? null : ItemStatus.valueOf(status.toUpperCase());
        ItemCriteria criteria = new ItemCriteria(q, st, categoryId, family, metal, emptyToNull(purity), locationId, minWt, maxWt,
                emptyToNull(stoneType), purchaseClass);
        return items.search(new ItemService.ItemSearch(criteria, minPrice, maxPrice, limit)).stream().map(ItemResponse::of).toList();
    }

    @GetMapping("/{id}")
    public ItemResponse get(@PathVariable long id) {
        return ItemResponse.of(items.detail(id));
    }

    /** Scan lookup: QR tag code today, RFID EPC later. */
    @GetMapping("/code/{code}")
    public ItemResponse byCode(@PathVariable String code) {
        return ItemResponse.of(items.requireByCode(code));
    }

    @PostMapping
    public ItemResponse createOpening(@RequestBody ItemRequest req) {
        return ItemResponse.of(items.createOpening(req.toNewItem(), req.vendorId(), req.purchaseClass()));
    }

    @PutMapping("/{id}")
    public ItemResponse update(@PathVariable long id, @RequestBody ItemUpdateRequest req) {
        return ItemResponse.of(items.update(id, req.toChanges()));
    }

    @PostMapping("/{id}/transfer/{locationId}")
    public ItemResponse transfer(@PathVariable long id, @PathVariable long locationId) {
        return ItemResponse.of(items.transfer(id, locationId));
    }

    @GetMapping("/ledger-check")
    public List<StatusMismatch> ledgerCheck() {
        return items.ledgerCheck();
    }

    private static String emptyToNull(String s) {
        return s == null || s.isBlank() ? null : s;
    }
}
