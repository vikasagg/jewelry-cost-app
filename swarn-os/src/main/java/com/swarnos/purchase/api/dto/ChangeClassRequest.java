package com.swarnos.purchase.api.dto;

import com.swarnos.inventory.domain.PurchaseClass;

public record ChangeClassRequest(PurchaseClass purchaseClass, String reason) {}
