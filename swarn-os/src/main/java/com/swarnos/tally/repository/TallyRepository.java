package com.swarnos.tally.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.tally.domain.Resolution;
import com.swarnos.tally.domain.TallyScan;
import com.swarnos.tally.domain.TallySession;
import com.swarnos.tally.domain.TallySessionView;
import com.swarnos.tally.domain.TallyStatus;
import com.swarnos.tally.domain.TallyVariance;
import com.swarnos.tally.domain.VarianceKind;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class TallyRepository {
    private static final RowMapper<TallySession> SESSION = (rs, i) -> new TallySession(rs.getLong("id"),
            Columns.date(rs, "business_date"), Columns.longOrNull(rs, "location_id"), Columns.longOrNull(rs, "category_id"),
            TallyStatus.valueOf(rs.getString("status")), rs.getInt("expected_count"), rs.getString("opened_by"),
            Columns.instant(rs, "opened_at"), rs.getString("closed_by"), Columns.instant(rs, "closed_at"), rs.getString("notes"));
    private static final String VIEW = """
            SELECT t.*, l.name AS location_name, c.name AS category_name,
                   (SELECT COUNT(*) FROM tally_scan s WHERE s.session_id = t.id) AS scanned_count,
                   (SELECT COUNT(*) FROM tally_variance v WHERE v.session_id = t.id) AS variance_count
            FROM tally_session t LEFT JOIN location l ON l.id = t.location_id LEFT JOIN category c ON c.id = t.category_id""";
    private static final RowMapper<TallySessionView> VIEW_MAPPER = (rs, i) -> new TallySessionView(SESSION.mapRow(rs, i),
            rs.getString("location_name"), rs.getString("category_name"), rs.getLong("scanned_count"), rs.getLong("variance_count"));
    private static final RowMapper<TallyScan> SCAN = (rs, i) -> new TallyScan(rs.getLong("id"), rs.getLong("session_id"),
            rs.getString("code"), Columns.longOrNull(rs, "item_id"), rs.getString("username"), Columns.instant(rs, "scanned_at"));
    private static final RowMapper<TallyVariance> VARIANCE = (rs, i) -> new TallyVariance(rs.getLong("id"), rs.getLong("session_id"),
            VarianceKind.valueOf(rs.getString("kind")), Columns.longOrNull(rs, "item_id"), rs.getString("code"),
            Columns.enumOrNull(rs, "resolution", Resolution.class), rs.getString("reason"), rs.getString("resolved_by"),
            Columns.instant(rs, "resolved_at"), rs.getString("item_name"));

    private final SqlSupport sql;

    public TallyRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public long insertSession(LocalDate date, Long locationId, Long categoryId, String openedBy, String notes) {
        return sql.insert("""
                INSERT INTO tally_session (business_date, location_id, category_id, status, opened_by, notes)
                VALUES (?,?,?, 'OPEN', ?, ?)""", date, locationId, categoryId, openedBy, notes);
    }

    public void insertExpected(long sessionId, List<Long> itemIds) {
        for (Long itemId : itemIds) sql.update("INSERT INTO tally_expected (session_id, item_id) VALUES (?,?)", sessionId, itemId);
        sql.update("UPDATE tally_session SET expected_count = ? WHERE id = ?", itemIds.size(), sessionId);
    }

    public List<Long> findExpectedIds(long sessionId) {
        return sql.list("SELECT item_id FROM tally_expected WHERE session_id = ? ORDER BY item_id", (rs, i) -> rs.getLong("item_id"),
                sessionId);
    }

    public Optional<TallySessionView> findView(long id) {
        return sql.one(VIEW + " WHERE t.id = ?", VIEW_MAPPER, id);
    }

    public List<TallySessionView> list(int limit) {
        return sql.list(VIEW + " ORDER BY t.id DESC LIMIT " + limit, VIEW_MAPPER);
    }

    public Optional<TallySession> findLatest() {
        return sql.one("SELECT * FROM tally_session ORDER BY id DESC LIMIT 1", SESSION);
    }

    public long countByStatus(TallyStatus status) {
        return sql.scalar("SELECT COUNT(*) FROM tally_session WHERE status = ?", Long.class, status.name());
    }

    public long countOn(LocalDate date) {
        return sql.scalar("SELECT COUNT(*) FROM tally_session WHERE business_date = ?", Long.class, date);
    }

    public List<TallyScan> findScans(long sessionId) {
        return sql.list("SELECT * FROM tally_scan WHERE session_id = ? ORDER BY id", SCAN, sessionId);
    }

    public boolean scanExists(long sessionId, String code) {
        return sql.scalar("SELECT COUNT(*) FROM tally_scan WHERE session_id = ? AND code = ?", Long.class, sessionId, code) > 0;
    }

    public void insertScan(long sessionId, String code, Long itemId, String username) {
        sql.update("INSERT INTO tally_scan (session_id, code, item_id, username) VALUES (?,?,?,?)", sessionId, code, itemId, username);
    }

    public void deleteScan(long sessionId, String code) {
        sql.update("DELETE FROM tally_scan WHERE session_id = ? AND code = ?", sessionId, code);
    }

    public List<TallyVariance> findVariances(long sessionId) {
        return sql.list("""
                SELECT v.*, i.name AS item_name FROM tally_variance v LEFT JOIN item i ON i.id = v.item_id
                WHERE v.session_id = ? ORDER BY v.kind, v.id""", VARIANCE, sessionId);
    }

    public Optional<TallyVariance> findVariance(long id) {
        return sql.one("""
                SELECT v.*, i.name AS item_name FROM tally_variance v LEFT JOIN item i ON i.id = v.item_id WHERE v.id = ?""",
                VARIANCE, id);
    }

    public void deleteOpenVariances(long sessionId) {
        sql.update("DELETE FROM tally_variance WHERE session_id = ? AND resolution IS NULL", sessionId);
    }

    public boolean varianceExists(long sessionId, VarianceKind kind, String code) {
        return sql.scalar("SELECT COUNT(*) FROM tally_variance WHERE session_id = ? AND kind = ? AND code = ?", Long.class,
                sessionId, kind.name(), code) > 0;
    }

    public void insertVariance(long sessionId, VarianceKind kind, Long itemId, String code) {
        sql.update("INSERT INTO tally_variance (session_id, kind, item_id, code) VALUES (?,?,?,?)", sessionId, kind.name(), itemId, code);
    }

    public void resolveVariance(long id, Resolution resolution, String reason, String by, Instant at) {
        sql.update("UPDATE tally_variance SET resolution = ?, reason = ?, resolved_by = ?, resolved_at = ? WHERE id = ?",
                resolution.name(), reason, by, Columns.timestamp(at), id);
    }

    public long countOpenVariances(long sessionId) {
        return sql.scalar("SELECT COUNT(*) FROM tally_variance WHERE session_id = ? AND resolution IS NULL", Long.class, sessionId);
    }

    public void close(long id, String by, Instant at) {
        sql.update("UPDATE tally_session SET status = 'CLOSED', closed_by = ?, closed_at = ? WHERE id = ?", by, Columns.timestamp(at), id);
    }

    public void reopen(long id) {
        sql.update("UPDATE tally_session SET status = 'OPEN', closed_by = NULL, closed_at = NULL WHERE id = ?", id);
    }
}
