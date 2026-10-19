package com.swarnos.tally.domain;

import static org.assertj.core.api.Assertions.assertThat;

import com.swarnos.inventory.domain.Item;
import com.swarnos.inventory.domain.ItemListing;
import com.swarnos.inventory.domain.ItemStatus;
import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.PricingMode;
import com.swarnos.settings.domain.ProductFamily;
import com.swarnos.settings.domain.Tracking;
import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;

class TallyReconciliationTest {
    private static ItemListing item(long id, String tag, String category, String net) {
        Item i = new Item(id, tag, null, 1, "Piece " + id, Metal.GOLD, "22K", new BigDecimal(net), BigDecimal.ZERO,
                new BigDecimal(net), null, null, null, null, 1, null, null, null, 1L, ItemStatus.IN_STOCK, null, null, null,
                null, null, null, null);
        return new ItemListing(i, category, category + " name", ProductFamily.GOLD, PricingMode.METAL, Tracking.PIECE,
                new BigDecimal("3"), MakingType.PERCENT, BigDecimal.TEN, BigDecimal.ZERO, "Counter 1", null, BigDecimal.ZERO,
                BigDecimal.ZERO, null);
    }

    private static TallyScan scan(String code, Long itemId) {
        return new TallyScan(0, 1, code, itemId, "stock", null);
    }

    @Test
    void findsMatchedMissingUnexpectedAndUnknown() {
        List<ItemListing> expected = List.of(item(1, "T1", "GCH", "10"), item(2, "T2", "GCH", "5.5"), item(3, "T3", "LGR", "3"));
        List<TallyScan> scans = List.of(scan("T1", 1L), scan("T3", 3L), scan("T9", 9L), scan("XYZ", null));
        TallyReconciliation r = TallyReconciliation.of(expected, scans, List.of(item(9, "T9", "GE", "2")));

        assertThat(r.scannedCount()).isEqualTo(4);
        assertThat(r.matchedCount()).isEqualTo(2);
        assertThat(r.missing()).extracting(TallyItem::tagCode).containsExactly("T2");
        assertThat(r.missingWt()).isEqualByComparingTo("5.500");
        assertThat(r.unexpected()).extracting(TallyItem::tagCode).containsExactly("T9");
        assertThat(r.unknown()).extracting(TallyScan::code).containsExactly("XYZ");
        assertThat(r.categories()).containsExactly(
                new CategoryCount("GCH", "GCH name", 2, 1, new BigDecimal("15.500"), new BigDecimal("10.000")),
                new CategoryCount("LGR", "LGR name", 1, 1, new BigDecimal("3.000"), new BigDecimal("3.000")));
    }

    @Test
    void scanCodesAreNormalised() {
        assertThat(TallyScan.normalize("  t000012 ")).isEqualTo("T000012");
    }
}
