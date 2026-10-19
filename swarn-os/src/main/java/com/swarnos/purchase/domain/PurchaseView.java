package com.swarnos.purchase.domain;

/** A purchase with the party's name and phone and its number of lines, for screens. */
public record PurchaseView(Purchase purchase, String partyName, String partyPhone, long lineCount) {}
