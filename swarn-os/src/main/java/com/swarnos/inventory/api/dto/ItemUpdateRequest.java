package com.swarnos.inventory.api.dto;

import com.swarnos.inventory.service.ItemService;
import com.swarnos.settings.domain.MakingType;
import java.math.BigDecimal;

public record ItemUpdateRequest(String name, BigDecimal grossWt, BigDecimal stoneWt, BigDecimal netWt, MakingType makingType,
                                BigDecimal makingValue, BigDecimal wastagePct, BigDecimal fixedPrice, String huid,
                                String designCode, String collection, String notes) {

    public ItemService.ItemChanges toChanges() {
        return new ItemService.ItemChanges(name, grossWt, stoneWt, netWt, makingType, makingValue, wastagePct, fixedPrice, huid,
                designCode, collection, notes);
    }
}
