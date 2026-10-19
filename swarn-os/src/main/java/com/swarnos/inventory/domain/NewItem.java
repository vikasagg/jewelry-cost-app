package com.swarnos.inventory.domain;

import com.swarnos.settings.domain.MakingType;
import java.math.BigDecimal;
import java.util.List;

/** What is needed to create an item, from a purchase line or opening stock. */
public record NewItem(Long categoryId, String tagCode, String name, String purityCode, BigDecimal grossWt, BigDecimal stoneWt,
                      BigDecimal netWt, MakingType makingType, BigDecimal makingValue, BigDecimal wastagePct,
                      BigDecimal fixedPrice, Integer quantity, String huid, String designCode, String collection,
                      Long locationId, BigDecimal costAmount, String notes, List<NewStone> stones) {

    public List<NewStone> presentStones() {
        return stones == null ? List.of() : stones.stream().filter(NewStone::isPresent).toList();
    }
}
