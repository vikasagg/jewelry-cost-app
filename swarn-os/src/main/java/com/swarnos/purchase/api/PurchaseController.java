package com.swarnos.purchase.api;

import com.swarnos.common.api.DateRange;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.inventory.domain.PurchaseClass;
import com.swarnos.purchase.api.dto.ChangeClassRequest;
import com.swarnos.purchase.api.dto.PurchaseRequest;
import com.swarnos.purchase.api.dto.PurchaseResponse;
import com.swarnos.purchase.api.dto.ReturnItemRequest;
import com.swarnos.purchase.domain.SettlementMode;
import com.swarnos.purchase.service.PurchaseService;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/purchases")
public class PurchaseController {
    private static final int DEFAULT_DAYS = 30;

    private final PurchaseService purchases;
    private final BusinessClock clock;

    public PurchaseController(PurchaseService purchases, BusinessClock clock) {
        this.purchases = purchases;
        this.clock = clock;
    }

    /** class = ALL, SEEN or UNSEEN (the Seen/Unseen show/hide filter). */
    @GetMapping
    public List<PurchaseResponse> list(@RequestParam(name = "class", defaultValue = "ALL") String purchaseClass,
                                       @RequestParam(required = false) SettlementMode mode,
                                       @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                                       @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        DateRange range = DateRange.lastDays(from, to, clock.today(), DEFAULT_DAYS);
        PurchaseClass cls = "ALL".equalsIgnoreCase(purchaseClass) ? null : PurchaseClass.valueOf(purchaseClass.toUpperCase());
        return purchases.list(cls, mode, range.from(), range.to()).stream().map(PurchaseResponse::summary).toList();
    }

    @GetMapping("/{id}")
    public PurchaseResponse get(@PathVariable long id) {
        return PurchaseResponse.of(purchases.detail(id), null);
    }

    @PostMapping
    public PurchaseResponse create(@RequestBody PurchaseRequest req) {
        PurchaseService.PurchaseResult result = purchases.create(req.toCommand());
        return PurchaseResponse.of(result.detail(), result.warnings());
    }

    @PutMapping("/{id}/class")
    public PurchaseResponse changeClass(@PathVariable long id, @RequestBody ChangeClassRequest req) {
        return PurchaseResponse.of(purchases.changeClass(id, req.purchaseClass(), req.reason()), null);
    }

    @PostMapping("/return-item/{itemId}")
    public Map<String, Long> returnItem(@PathVariable long itemId, @RequestBody ReturnItemRequest req) {
        return Map.of("item_id", purchases.returnToVendor(itemId, req.reason()));
    }
}
