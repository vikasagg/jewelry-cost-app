package com.swarnos.common.persistence;

import com.swarnos.common.money.Decimals;
import java.math.BigDecimal;
import java.sql.Date;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;

/** Null-safe typed column readers for row mappers. */
public final class Columns {
    private Columns() {}

    public static BigDecimal decimal(ResultSet rs, String col) throws SQLException {
        return Decimals.roundOrNull(rs.getBigDecimal(col));
    }

    public static BigDecimal decimalOrZero(ResultSet rs, String col) throws SQLException {
        return Decimals.orZero(rs.getBigDecimal(col));
    }

    public static Long longOrNull(ResultSet rs, String col) throws SQLException {
        long v = rs.getLong(col);
        return rs.wasNull() ? null : v;
    }

    public static Integer intOrNull(ResultSet rs, String col) throws SQLException {
        int v = rs.getInt(col);
        return rs.wasNull() ? null : v;
    }

    public static LocalDate date(ResultSet rs, String col) throws SQLException {
        Date d = rs.getDate(col);
        return d == null ? null : d.toLocalDate();
    }

    public static Instant instant(ResultSet rs, String col) throws SQLException {
        Timestamp t = rs.getTimestamp(col);
        return t == null ? null : t.toInstant();
    }

    public static <E extends Enum<E>> E enumOrNull(ResultSet rs, String col, Class<E> type) throws SQLException {
        String v = rs.getString(col);
        return v == null ? null : Enum.valueOf(type, v);
    }

    public static Timestamp timestamp(Instant i) {
        return i == null ? null : Timestamp.from(i);
    }

    public static String name(Enum<?> e) {
        return e == null ? null : e.name();
    }
}
