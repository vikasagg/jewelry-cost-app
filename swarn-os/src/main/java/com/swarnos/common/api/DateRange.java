package com.swarnos.common.api;

import java.time.LocalDate;

/** Date filter of list and report endpoints, with the screen's defaults. */
public record DateRange(LocalDate from, LocalDate to) {

    /** Default: first of the month up to today. */
    public static DateRange monthToDate(LocalDate from, LocalDate to, LocalDate today) {
        LocalDate t = to == null ? today : to;
        return new DateRange(from == null ? t.withDayOfMonth(1) : from, t);
    }

    /** Default: the last {@code days} days up to today. */
    public static DateRange lastDays(LocalDate from, LocalDate to, LocalDate today, int days) {
        LocalDate t = to == null ? today : to;
        return new DateRange(from == null ? t.minusDays(days) : from, t);
    }
}
