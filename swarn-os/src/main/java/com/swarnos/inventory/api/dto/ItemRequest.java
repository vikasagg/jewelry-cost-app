package com.swarnos.inventory.api.dto;

import com.swarnos.inventory.domain.NewItem;
import com.swarnos.inventory.domain.PurchaseClass;
import com.swarnos.settings.domain.MakingType;
import java.math.BigDecimal;
import java.util.List;

/** Opening stock entry, and the item part of a purchase line. */
public record ItemRequest(Long categoryId, String tagCode, String name, String purityCode, BigDecimal grossWt,
                          BigDecimal stoneWt, BigDecimal netWt, MakingType makingType, BigDecimal makingValue,
                          BigDecimal wastagePct, BigDecimal fixedPrice, Integer quantity, String huid, String designCode,
                          String collection, Long locationId, BigDecimal costAmount, String notes, List<StoneRequest> stones,
                          Long vendorId, PurchaseClass purchaseClass) {

    public NewItem toNewItem() {
        return new NewItem(categoryId, tagCode, name, purityCode, grossWt, stoneWt, netWt, makingType, makingValue, wastagePct,
                fixedPrice, quantity, huid, designCode, collection, locationId, costAmount, notes,
                stones == null ? List.of() : stones.stream().map(StoneRequest::toNewStone).toList());
    }
}
