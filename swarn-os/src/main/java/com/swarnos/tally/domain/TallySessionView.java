package com.swarnos.tally.domain;

public record TallySessionView(TallySession session, String locationName, String categoryName, long scannedCount,
                               long varianceCount) {}
