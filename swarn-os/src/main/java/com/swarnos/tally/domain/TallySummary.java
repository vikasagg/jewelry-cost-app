package com.swarnos.tally.domain;

import java.util.List;

/** Everything the tally screen shows for one session. */
public record TallySummary(TallySessionView view, TallyReconciliation reconciliation, List<TallyVariance> variances,
                           long repairBucket, long karigarBucket, List<RecentScan> recentScans) {}
