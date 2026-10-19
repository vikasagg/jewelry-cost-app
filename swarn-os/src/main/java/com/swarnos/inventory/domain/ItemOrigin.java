package com.swarnos.inventory.domain;

/** Where a new item came from: opening stock or a purchase (with its vendor and Seen/Unseen class). */
public record ItemOrigin(MovementType movementType, String docType, Long docId, Long vendorId, Long purchaseId,
                         PurchaseClass purchaseClass) {

    public static ItemOrigin opening(Long vendorId, PurchaseClass purchaseClass) {
        return new ItemOrigin(MovementType.OPENING, "OPENING", null, vendorId, null, purchaseClass);
    }

    public static ItemOrigin purchase(long purchaseId, long vendorId, PurchaseClass purchaseClass) {
        return new ItemOrigin(MovementType.PURCHASE, "PURCHASE", purchaseId, vendorId, purchaseId, purchaseClass);
    }
}
