package com.swarnos.inventory.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.swarnos.inventory.domain.Item;
import com.swarnos.inventory.domain.ItemListing;
import com.swarnos.inventory.domain.ItemStatus;
import com.swarnos.inventory.domain.PriceBreakdown;
import com.swarnos.inventory.domain.PurchaseClass;
import com.swarnos.inventory.domain.StockMovement;
import com.swarnos.inventory.domain.Stone;
import com.swarnos.inventory.service.ItemService;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.PricingMode;
import com.swarnos.settings.domain.ProductFamily;
import com.swarnos.settings.domain.Tracking;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

/**
 * An item as shown on screen: master data, category, price at today's rate and
 * (on the detail view) stones and movements. Cost and purchase class are left
 * out for roles that may not see them.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ItemResponse(long id, String tagCode, String rfidEpc, long categoryId, String categoryCode, String categoryName,
                           ProductFamily family, PricingMode pricingMode, Tracking tracking, BigDecimal gstPct, String name,
                           Metal metal, String purityCode, BigDecimal grossWt, BigDecimal stoneWt, BigDecimal netWt,
                           MakingType makingType, BigDecimal makingValue, BigDecimal wastagePct, BigDecimal fixedPrice,
                           int quantity, String huid, String designCode, String collection, Long locationId,
                           String locationName, ItemStatus status, Long vendorId, String vendorName, Long purchaseId,
                           PurchaseClass purchaseClass, BigDecimal costAmount, String notes, String createdBy,
                           Instant createdAt, BigDecimal stoneValue, BigDecimal stoneCarat, String stoneType, BigDecimal price,
                           PriceBreakdown priceBreakdown, List<Stone> stones, List<StockMovement> movements) {

    public static ItemResponse of(ItemService.PricedItem p) {
        return of(p, null, null);
    }

    public static ItemResponse of(ItemService.ItemDetail d) {
        return of(d.item(), d.stones(), d.movements());
    }

    private static ItemResponse of(ItemService.PricedItem p, List<Stone> stones, List<StockMovement> movements) {
        ItemListing l = p.listing();
        Item i = l.item();
        boolean cost = CurrentUser.can(Permission.VIEW_COST);
        boolean cls = CurrentUser.can(Permission.VIEW_PURCHASE_CLASS);
        return new ItemResponse(i.id(), i.tagCode(), i.rfidEpc(), i.categoryId(), l.categoryCode(), l.categoryName(), l.family(),
                l.pricingMode(), l.tracking(), l.gstPct(), i.name(), i.metal(), i.purityCode(), i.grossWt(), i.stoneWt(), i.netWt(),
                i.makingType(), i.makingValue(), i.wastagePct(), i.fixedPrice(), i.quantity(), i.huid(), i.designCode(),
                i.collection(), i.locationId(), l.locationName(), i.status(), i.vendorId(), l.vendorName(), i.purchaseId(),
                cls ? i.purchaseClass() : null, cost ? i.costAmount() : null, i.notes(), i.createdBy(), i.createdAt(),
                l.stoneValue(), l.stoneCarat(), l.stoneType(), p.total(), p.price(), stones, movements);
    }
}
