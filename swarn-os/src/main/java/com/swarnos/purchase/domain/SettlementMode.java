package com.swarnos.purchase.domain;

/** How a purchase was paid (BRD §8): one leg, several (MIXED), or nothing yet (CREDIT). */
public enum SettlementMode {
    CASH, BANK, GOLD, SILVER, MIXED, CREDIT
}
