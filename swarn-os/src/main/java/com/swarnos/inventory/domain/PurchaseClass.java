package com.swarnos.inventory.domain;

/**
 * How stock was bought (BRD §9): SEEN = GST invoice and no cash; UNSEEN = no GST
 * invoice or paid in cash. A reporting class only; it never hides stock.
 */
public enum PurchaseClass {
    SEEN, UNSEEN;

    public static PurchaseClass classify(boolean hasGstInvoice, boolean paidAnyCash) {
        return hasGstInvoice && !paidAnyCash ? SEEN : UNSEEN;
    }
}
