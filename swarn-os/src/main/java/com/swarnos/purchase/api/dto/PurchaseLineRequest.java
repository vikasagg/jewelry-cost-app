package com.swarnos.purchase.api.dto;

import com.swarnos.inventory.api.dto.StoneRequest;
import com.swarnos.inventory.domain.NewItem;
import com.swarnos.purchase.domain.OldMetalLine;
import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;
import java.util.List;

/**
 * One purchase line. Finished jewellery and gifting use the item fields (with the
 * line's purchase value in cost_amount); old metal uses description, metal,
 * purity, weights, deduction and an optional rate.
 */
public record PurchaseLineRequest(Long categoryId, String tagCode, String name, String purityCode, BigDecimal grossWt,
                                  BigDecimal stoneWt, BigDecimal netWt, MakingType makingType, BigDecimal makingValue,
                                  BigDecimal wastagePct, BigDecimal fixedPrice, Integer quantity, String huid, String designCode,
                                  String collection, Long locationId, BigDecimal costAmount, String notes,
                                  List<StoneRequest> stones, String description, Metal metal, BigDecimal deductionPct,
                                  BigDecimal rate) {

    public NewItem toNewItem() {
        return new NewItem(categoryId, tagCode, name, purityCode, grossWt, stoneWt, netWt, makingType, makingValue, wastagePct,
                fixedPrice, quantity, huid, designCode, collection, locationId, costAmount, notes,
                stones == null ? List.of() : stones.stream().map(StoneRequest::toNewStone).toList());
    }

    public OldMetalLine toOldMetal() {
        return new OldMetalLine(description, metal, purityCode, grossWt, netWt, deductionPct, rate);
    }
}
