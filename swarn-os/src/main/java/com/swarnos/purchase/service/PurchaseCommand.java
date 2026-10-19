package com.swarnos.purchase.service;

import com.swarnos.inventory.domain.NewItem;
import com.swarnos.inventory.domain.PurchaseClass;
import com.swarnos.purchase.domain.OldMetalLine;
import com.swarnos.purchase.domain.PaymentLegs;
import com.swarnos.purchase.domain.PurchaseKind;
import java.math.BigDecimal;
import java.util.List;

/**
 * A purchase to record. Item kinds use {@code items} (each with its purchase value
 * in cost_amount); OLD_METAL uses {@code oldMetal}.
 */
public record PurchaseCommand(Long partyId, PurchaseKind kind, String gstInvoiceNo, BigDecimal gstPct,
                              PurchaseClass requestedClass, String notes, List<NewItem> items, List<OldMetalLine> oldMetal,
                              PaymentLegs payment) {}
