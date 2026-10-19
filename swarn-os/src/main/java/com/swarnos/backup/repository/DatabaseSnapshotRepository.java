package com.swarnos.backup.repository;

import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.tenant.domain.StorageMode;
import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import javax.sql.DataSource;
import org.springframework.jdbc.datasource.DataSourceUtils;
import org.springframework.stereotype.Repository;

/** Reads every row of the current shop's tables, and writes them back into a (new) shop's database. */
@Repository
public class DatabaseSnapshotRepository {
    private final SqlSupport sql;
    private final DataSource dataSource;

    public DatabaseSnapshotRepository(SqlSupport sql, DataSource dataSource) {
        this.sql = sql;
        this.dataSource = dataSource;
    }

    public Map<String, List<Map<String, Object>>> export(List<String> tables) {
        Map<String, List<Map<String, Object>>> out = new LinkedHashMap<>();
        for (String t : tables) out.put(t, sql.rows("SELECT * FROM " + t));
        return out;
    }

    /** Replaces every table's content in one transaction and moves id sequences past the restored ids. */
    public long replaceAll(List<String> tables, Map<String, List<Map<String, Object>>> data, StorageMode mode) {
        Connection c = DataSourceUtils.getConnection(dataSource);
        try {
            boolean autoCommit = c.getAutoCommit();
            c.setAutoCommit(false);
            try {
                List<String> reversed = new ArrayList<>(tables);
                Collections.reverse(reversed);
                for (String t : reversed) {
                    try (Statement st = c.createStatement()) {
                        st.executeUpdate("DELETE FROM " + t);
                    }
                }
                long rows = 0;
                for (String t : tables) rows += insertAll(c, t, data.getOrDefault(t, List.of()));
                for (String t : tables) resetIdentity(c, t, mode);
                c.commit();
                return rows;
            } catch (SQLException | RuntimeException e) {
                c.rollback();
                throw e;
            } finally {
                c.setAutoCommit(autoCommit);
            }
        } catch (SQLException e) {
            throw new IllegalStateException("Restore failed: " + e.getMessage(), e);
        } finally {
            DataSourceUtils.releaseConnection(c, dataSource);
        }
    }

    private static long insertAll(Connection c, String table, List<Map<String, Object>> rows) throws SQLException {
        if (rows.isEmpty()) return 0;
        Map<String, Integer> types = new LinkedHashMap<>();
        try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery("SELECT * FROM " + table + " WHERE 1 = 0")) {
            ResultSetMetaData md = rs.getMetaData();
            for (int i = 1; i <= md.getColumnCount(); i++) types.put(md.getColumnName(i).toLowerCase(), md.getColumnType(i));
        }
        List<String> cols = new ArrayList<>(types.keySet());
        String insert = "INSERT INTO " + table + " (" + String.join(",", cols) + ") VALUES ("
                + String.join(",", Collections.nCopies(cols.size(), "?")) + ")";
        try (PreparedStatement ps = c.prepareStatement(insert)) {
            for (Map<String, Object> row : rows) {
                for (int i = 0; i < cols.size(); i++) {
                    Object v = row.get(cols.get(i));
                    int type = types.get(cols.get(i));
                    if (v == null) ps.setNull(i + 1, type); else ps.setObject(i + 1, convert(v, type), type);
                }
                ps.addBatch();
            }
            ps.executeBatch();
        }
        return rows.size();
    }

    /** Backup files hold JSON values; convert them to the column's SQL type. */
    private static Object convert(Object v, int type) {
        String s = v.toString();
        return switch (type) {
            case Types.NUMERIC, Types.DECIMAL -> new BigDecimal(s);
            case Types.INTEGER, Types.SMALLINT -> Integer.valueOf(s);
            case Types.BIGINT -> Long.valueOf(s);
            case Types.BOOLEAN, Types.BIT -> Boolean.valueOf(s);
            case Types.DATE -> java.sql.Date.valueOf(s.substring(0, 10));
            case Types.TIMESTAMP, Types.TIMESTAMP_WITH_TIMEZONE -> v instanceof Number n ? new Timestamp(n.longValue())
                    : Timestamp.from(OffsetDateTime.parse(s.length() == 19 ? s + "Z" : s.replace("+0000", "+00:00")).toInstant());
            default -> s;
        };
    }

    private static void resetIdentity(Connection c, String table, StorageMode mode) throws SQLException {
        try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery("SELECT * FROM " + table + " WHERE 1 = 0")) {
            ResultSetMetaData md = rs.getMetaData();
            if (!md.getColumnName(1).equalsIgnoreCase("id") || md.getColumnType(1) != Types.BIGINT) return;
        }
        long next;
        try (Statement st = c.createStatement(); ResultSet rs = st.executeQuery("SELECT COALESCE(MAX(id), 0) + 1 FROM " + table)) {
            rs.next();
            next = rs.getLong(1);
        }
        try (Statement st = c.createStatement()) {
            st.execute(mode == StorageMode.CLOUD
                    ? "SELECT setval(pg_get_serial_sequence('" + table + "', 'id'), " + next + ", false)"
                    : "ALTER TABLE " + table + " ALTER COLUMN id RESTART WITH " + next);
        }
    }
}
