package com.swarnos.tally.domain;

import com.swarnos.inventory.domain.ItemListing;
import com.swarnos.inventory.domain.ItemStatus;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;

/** An item as listed by the tally (missing or unexpected). */
public record TallyItem(long id, String tagCode, String name, BigDecimal netWt, Metal metal, String categoryCode,
                        ItemStatus status, String locationName) {

    public static TallyItem of(ItemListing l) {
        return new TallyItem(l.item().id(), l.item().tagCode(), l.item().name(), l.item().netWt(), l.item().metal(),
                l.categoryCode(), l.item().status(), l.locationName());
    }
}
