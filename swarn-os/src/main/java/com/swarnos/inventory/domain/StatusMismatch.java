package com.swarnos.inventory.domain;

/** An item whose cached status differs from its last stock movement. */
public record StatusMismatch(long id, String tagCode, ItemStatus cachedStatus, ItemStatus ledgerStatus) {}
