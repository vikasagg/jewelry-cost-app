package com.swarnos.tally.domain;

import com.swarnos.common.money.Decimals;
import com.swarnos.inventory.domain.ItemListing;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.stream.Collectors;

/**
 * Compares what the system expects on the counter with what was scanned:
 * matched, missing, unexpected and unknown tags, and counts per category.
 * A scan never changes stock; this only reports.
 */
public record TallyReconciliation(long scannedCount, long matchedCount, List<TallyItem> missing, List<TallyItem> unexpected,
                                  List<TallyScan> unknown, List<CategoryCount> categories, BigDecimal missingWt) {

    /**
     * @param expected  items expected when the session opened
     * @param scans     every scan of the session
     * @param scannedNotExpected listings of scanned items that were not expected
     */
    public static TallyReconciliation of(List<ItemListing> expected, List<TallyScan> scans, List<ItemListing> scannedNotExpected) {
        Set<Long> scannedIds = scans.stream().filter(s -> s.itemId() != null).map(TallyScan::itemId).collect(Collectors.toSet());
        Set<Long> expectedIds = expected.stream().map(l -> l.item().id()).collect(Collectors.toSet());

        List<TallyItem> missing = expected.stream().filter(l -> !scannedIds.contains(l.item().id()))
                .map(TallyItem::of).sorted(Comparator.comparing(TallyItem::tagCode)).toList();
        List<TallyItem> unexpected = scannedNotExpected.stream().filter(l -> !expectedIds.contains(l.item().id()))
                .map(TallyItem::of).sorted(Comparator.comparing(TallyItem::tagCode)).toList();
        List<TallyScan> unknown = scans.stream().filter(s -> s.itemId() == null).toList();
        long matched = scannedIds.stream().filter(expectedIds::contains).count();

        Map<String, List<ItemListing>> byCategory = expected.stream()
                .collect(Collectors.groupingBy(ItemListing::categoryCode, TreeMap::new, Collectors.toList()));
        List<CategoryCount> categories = new ArrayList<>();
        byCategory.forEach((code, list) -> {
            List<ItemListing> found = list.stream().filter(l -> scannedIds.contains(l.item().id())).toList();
            categories.add(new CategoryCount(code, list.get(0).categoryName(), list.size(), found.size(), netWeight(list),
                    netWeight(found)));
        });
        BigDecimal missingWt = Decimals.round(missing.stream().map(TallyItem::netWt).reduce(BigDecimal.ZERO, BigDecimal::add));
        return new TallyReconciliation(scans.size(), matched, missing, unexpected, unknown, categories, missingWt);
    }

    private static BigDecimal netWeight(List<ItemListing> items) {
        return Decimals.round(items.stream().map(l -> l.item().netWt()).reduce(BigDecimal.ZERO, BigDecimal::add));
    }
}
