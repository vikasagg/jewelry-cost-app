package com.swarnos.sales.domain;

/** A sale with its customer's details and number of items, for screens. */
public record SaleView(Sale sale, String customerName, String customerPhone, String customerAddress, String customerGstin,
                       String customerPan, long itemCount) {}
