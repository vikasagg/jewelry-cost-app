package com.swarnos.reports.domain;

/** A report column; type is text, money, wt, num, int, date or datetime (drives formatting on screen). */
public record Column(String key, String label, String type) {

    /** Parses "key:Label:type" (type optional, default text). */
    public static Column of(String spec) {
        String[] p = spec.split(":");
        return new Column(p[0], p[1], p.length > 2 ? p[2] : "text");
    }

    public boolean isNumeric() {
        return type.equals("money") || type.equals("wt") || type.equals("int");
    }
}
