package com.swarnos.repair.domain;

import java.util.Map;
import java.util.Set;

/** Steps of a repair job and the moves allowed between them. */
public enum RepairStatus {
    RECEIVED, WITH_KARIGAR, IN_PROGRESS, READY, DELIVERED;

    private static final Map<RepairStatus, Set<RepairStatus>> NEXT = Map.of(
            RECEIVED, Set.of(WITH_KARIGAR, IN_PROGRESS, READY),
            WITH_KARIGAR, Set.of(READY, IN_PROGRESS),
            IN_PROGRESS, Set.of(READY, WITH_KARIGAR),
            READY, Set.of(DELIVERED, IN_PROGRESS),
            DELIVERED, Set.of());

    public boolean canMoveTo(RepairStatus next) {
        return NEXT.get(this).contains(next);
    }

    /** Piece is physically in the shop (counted as the repair bucket in the tally). */
    public boolean isInShop() {
        return this == RECEIVED || this == IN_PROGRESS || this == READY;
    }
}
