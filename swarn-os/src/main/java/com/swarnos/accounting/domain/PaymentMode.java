package com.swarnos.accounting.domain;

/** How money moves; cash goes to the cash book, everything else to the bank book. */
public enum PaymentMode {
    CASH, UPI, CARD, BANK, CHEQUE;

    public Book book() {
        return this == CASH ? Book.CASH : Book.BANK;
    }
}
