package com.swarnos.inventory.domain;

import java.util.Set;

/**
 * A request to change stock: the item must currently be in one of
 * {@code allowedFrom}; afterwards it is {@code statusAfter} (and optionally moved).
 */
public record StockMove(long itemId, MovementType type, int qty, Set<ItemStatus> allowedFrom, ItemStatus statusAfter,
                        Long toLocationId, String docType, Long docId, String note) {}
