package com.swarnos.inventory.domain;

import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.ProductFamily;
import java.math.BigDecimal;

/** Stock search filters; null means "any". */
public record ItemCriteria(String text, ItemStatus status, Long categoryId, ProductFamily family, Metal metal, String purity,
                           Long locationId, BigDecimal minWt, BigDecimal maxWt, String stoneType, PurchaseClass purchaseClass) {

    public static ItemCriteria inStock() {
        return new ItemCriteria(null, ItemStatus.IN_STOCK, null, null, null, null, null, null, null, null, null);
    }
}
