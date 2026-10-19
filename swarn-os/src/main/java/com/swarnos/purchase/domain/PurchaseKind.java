package com.swarnos.purchase.domain;

/** FINISHED and GIFTING lines become tagged items; OLD_METAL goes into the metal book by fine weight. */
public enum PurchaseKind {
    FINISHED, OLD_METAL, GIFTING;

    public boolean createsItems() {
        return this != OLD_METAL;
    }
}
