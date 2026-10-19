package com.aijewel.erp.common;

import java.time.LocalDate;
import java.util.Map;

/** Reads typed values from database rows and JSON request bodies. */
public final class Rows {
    private Rows() {}

    public static String str(Object o) {
        return o == null ? "" : o.toString().trim();
    }

    public static String strOrNull(Object o) {
        String s = str(o);
        return s.isEmpty() ? null : s;
    }

    public static long id(Object o) {
        if (o instanceof Number n) return n.longValue();
        try {
            return Long.parseLong(str(o));
        } catch (NumberFormatException e) {
            throw ApiException.bad("Missing or wrong id: " + o);
        }
    }

    public static Long idOrNull(Object o) {
        return o == null || str(o).isEmpty() ? null : id(o);
    }

    public static int integer(Object o, int fallback) {
        if (o == null || str(o).isEmpty()) return fallback;
        if (o instanceof Number n) return n.intValue();
        return Integer.parseInt(str(o));
    }

    public static LocalDate date(Object o) {
        if (o == null || str(o).isEmpty()) return null;
        if (o instanceof LocalDate d) return d;
        if (o instanceof java.sql.Date d) return d.toLocalDate();
        if (o instanceof java.util.Date d) return new java.sql.Date(d.getTime()).toLocalDate();
        return LocalDate.parse(str(o).substring(0, 10));
    }

    public static long id(Map<String, Object> row) {
        return id(row.get("id"));
    }
}
