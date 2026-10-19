package com.swarnos.inventory.domain;

import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;
import java.time.Instant;

/** One tagged piece (or a quantity of a gifting SKU). Making and wastage override the category when set. */
public record Item(long id, String tagCode, String rfidEpc, long categoryId, String name, Metal metal, String purityCode,
                   BigDecimal grossWt, BigDecimal stoneWt, BigDecimal netWt, MakingType makingType, BigDecimal makingValue,
                   BigDecimal wastagePct, BigDecimal fixedPrice, int quantity, String huid, String designCode,
                   String collection, Long locationId, ItemStatus status, Long vendorId, Long purchaseId,
                   PurchaseClass purchaseClass, BigDecimal costAmount, String notes, String createdBy, Instant createdAt) {}
