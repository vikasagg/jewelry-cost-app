package com.swarnos.tally.domain;

import java.time.Instant;

/** A difference found by the tally; {@code name} is the item's name, filled when reading. */
public record TallyVariance(long id, long sessionId, VarianceKind kind, Long itemId, String code, Resolution resolution,
                            String reason, String resolvedBy, Instant resolvedAt, String name) {

    public boolean isOpen() {
        return resolution == null;
    }
}
