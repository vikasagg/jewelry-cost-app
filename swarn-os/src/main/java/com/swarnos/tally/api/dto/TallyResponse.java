package com.swarnos.tally.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonUnwrapped;
import com.swarnos.tally.domain.CategoryCount;
import com.swarnos.tally.domain.RecentScan;
import com.swarnos.tally.domain.TallyItem;
import com.swarnos.tally.domain.TallyReconciliation;
import com.swarnos.tally.domain.TallyScan;
import com.swarnos.tally.domain.TallySession;
import com.swarnos.tally.domain.TallySessionView;
import com.swarnos.tally.domain.TallySummary;
import com.swarnos.tally.domain.TallyVariance;
import java.math.BigDecimal;
import java.util.List;

/** A tally session: summary row in the list, full comparison on the session screen. */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record TallyResponse(@JsonUnwrapped TallySession session, String locationName, String categoryName, Long scannedCount,
                            Long varianceCount, Long matchedCount, List<TallyItem> missing, List<TallyItem> unexpected,
                            List<TallyScan> unknown, List<CategoryCount> categories, BigDecimal missingWt,
                            List<TallyVariance> variances, Long repairBucket, Long karigarBucket, List<RecentScan> recentScans,
                            Integer added) {

    public static TallyResponse row(TallySessionView v) {
        return new TallyResponse(v.session(), v.locationName(), v.categoryName(), v.scannedCount(), v.varianceCount(), null, null,
                null, null, null, null, null, null, null, null, null);
    }

    public static TallyResponse of(TallySummary s) {
        return of(s, null);
    }

    public static TallyResponse of(TallySummary s, Integer added) {
        TallySessionView v = s.view();
        TallyReconciliation r = s.reconciliation();
        return new TallyResponse(v.session(), v.locationName(), v.categoryName(), r.scannedCount(), v.varianceCount(),
                r.matchedCount(), r.missing(), r.unexpected(), r.unknown(), r.categories(), r.missingWt(), s.variances(),
                s.repairBucket(), s.karigarBucket(), s.recentScans(), added);
    }
}
