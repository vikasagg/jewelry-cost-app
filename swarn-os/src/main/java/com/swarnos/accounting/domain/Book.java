package com.swarnos.accounting.domain;

import com.swarnos.settings.domain.Metal;
import java.util.List;

/**
 * Books (BRD §5.1, §8): CASH and BANK in rupees, GOLD / SILVER / PLATINUM in
 * fine grams, PARTY in rupees per party. Debit is "in" (or "the party owes us").
 */
public enum Book {
    CASH, BANK, GOLD, SILVER, PLATINUM, PARTY;

    /** The books shown on the Books screen and dashboard. */
    public static final List<Book> SHOP_BOOKS = List.of(CASH, BANK, GOLD, SILVER, PLATINUM);

    public boolean isMetal() {
        return this == GOLD || this == SILVER || this == PLATINUM;
    }

    public static Book forMetal(Metal metal) {
        return Book.valueOf(metal.name());
    }
}
