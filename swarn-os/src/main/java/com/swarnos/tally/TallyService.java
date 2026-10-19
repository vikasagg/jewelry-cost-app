package com.swarnos.tally;

import static com.swarnos.common.Rows.str;

import com.swarnos.auth.CurrentUser;
import com.swarnos.auth.Permission;
import com.swarnos.common.ApiException;
import com.swarnos.common.AuditService;
import com.swarnos.common.BusinessClock;
import com.swarnos.common.Db;
import com.swarnos.common.Num;
import com.swarnos.common.Rows;
import com.swarnos.config.ConfigService;
import com.swarnos.stock.StockLedger;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Daily stock tally (BRD §5.2): open a session with the expected list, scan
 * tags (QR now, RFID bulk reads later through the same endpoint), compare,
 * resolve each variance with a reason, then close. A scan never changes stock
 * by itself; only an approved variance posts an adjustment.
 */
@Service
public class TallyService {
    private final Db db;
    private final StockLedger stock;
    private final ConfigService config;
    private final AuditService audit;
    private final BusinessClock clock;

    public TallyService(Db db, StockLedger stock, ConfigService config, AuditService audit, BusinessClock clock) {
        this.db = db;
        this.stock = stock;
        this.config = config;
        this.audit = audit;
        this.clock = clock;
    }

    @Transactional
    public Map<String, Object> open(Long locationId, Long categoryId, String notes) {
        CurrentUser.require(Permission.TALLY_CAPTURE);
        long id = db.insert("""
                INSERT INTO tally_session (business_date, location_id, category_id, status, opened_by, notes)
                VALUES (?,?,?, 'OPEN', ?, ?)""", clock.today(), locationId, categoryId, CurrentUser.usernameOrSystem(), notes);
        int n = db.update("""
                INSERT INTO tally_expected (session_id, item_id)
                SELECT ?, i.id FROM item i WHERE i.status = 'IN_STOCK'
                  AND (CAST(? AS BIGINT) IS NULL OR i.location_id = ?) AND (CAST(? AS BIGINT) IS NULL OR i.category_id = ?)""",
                id, locationId, locationId, categoryId, categoryId);
        db.update("UPDATE tally_session SET expected_count = ? WHERE id = ?", n, id);
        audit.log("TALLY_OPEN", "tally", id, "expected " + n);
        return summary(id);
    }

    /** Records scanned codes. Repeats inside a session are ignored, so staff can rescan freely. */
    @Transactional
    public Map<String, Object> scan(long id, List<String> codes) {
        CurrentUser.require(Permission.TALLY_CAPTURE);
        requireOpen(id);
        int added = 0;
        for (String raw : codes) {
            String code = raw == null ? "" : raw.trim().toUpperCase();
            if (code.isEmpty()) continue;
            if (db.opt("SELECT id FROM tally_scan WHERE session_id = ? AND code = ?", id, code).isPresent()) continue;
            Long itemId = db.value("SELECT id FROM item WHERE UPPER(tag_code) = ? OR UPPER(rfid_epc) = ?", Long.class, code, code);
            db.update("INSERT INTO tally_scan (session_id, code, item_id, username) VALUES (?,?,?,?)",
                    id, code, itemId, CurrentUser.usernameOrSystem());
            added++;
        }
        Map<String, Object> s = summary(id);
        s.put("added", added);
        return s;
    }

    @Transactional
    public Map<String, Object> unscan(long id, String code) {
        CurrentUser.require(Permission.TALLY_CAPTURE);
        requireOpen(id);
        db.update("DELETE FROM tally_scan WHERE session_id = ? AND code = ?", id, code.trim().toUpperCase());
        return summary(id);
    }

    public Map<String, Object> summary(long id) {
        Map<String, Object> s = new LinkedHashMap<>(db.one("""
                SELECT t.*, l.name AS location_name, c.name AS category_name FROM tally_session t
                LEFT JOIN location l ON l.id = t.location_id LEFT JOIN category c ON c.id = t.category_id
                WHERE t.id = ?""", "Tally session not found", id));
        List<Map<String, Object>> missing = db.rows("""
                SELECT i.id, i.tag_code, i.name, i.net_wt, i.metal, c.code AS category_code FROM tally_expected e
                JOIN item i ON i.id = e.item_id JOIN category c ON c.id = i.category_id
                WHERE e.session_id = ? AND NOT EXISTS (SELECT 1 FROM tally_scan s WHERE s.session_id = e.session_id AND s.item_id = e.item_id)
                ORDER BY i.tag_code""", id);
        List<Map<String, Object>> unexpected = db.rows("""
                SELECT i.id, i.tag_code, i.name, i.status, i.net_wt, l.name AS location_name FROM tally_scan s
                JOIN item i ON i.id = s.item_id LEFT JOIN location l ON l.id = i.location_id
                WHERE s.session_id = ? AND NOT EXISTS (SELECT 1 FROM tally_expected e WHERE e.session_id = s.session_id AND e.item_id = s.item_id)
                ORDER BY i.tag_code""", id);
        List<Map<String, Object>> unknown = db.rows("SELECT code, scanned_at FROM tally_scan WHERE session_id = ? AND item_id IS NULL ORDER BY id", id);
        long scanned = db.value("SELECT COUNT(*) FROM tally_scan WHERE session_id = ?", Long.class, id);
        long matched = db.value("""
                SELECT COUNT(*) FROM tally_scan s JOIN tally_expected e ON e.session_id = s.session_id AND e.item_id = s.item_id
                WHERE s.session_id = ?""", Long.class, id);

        s.put("scanned_count", scanned);
        s.put("matched_count", matched);
        s.put("missing", missing);
        s.put("unexpected", unexpected);
        s.put("unknown", unknown);
        s.put("categories", db.rows("""
                SELECT c.code, c.name,
                       COUNT(e.item_id) AS expected,
                       SUM(CASE WHEN EXISTS (SELECT 1 FROM tally_scan s WHERE s.session_id = e.session_id AND s.item_id = e.item_id)
                                THEN 1 ELSE 0 END) AS physical,
                       COALESCE(SUM(i.net_wt), 0) AS expected_wt,
                       COALESCE(SUM(CASE WHEN EXISTS (SELECT 1 FROM tally_scan s WHERE s.session_id = e.session_id AND s.item_id = e.item_id)
                                THEN i.net_wt ELSE 0 END), 0) AS physical_wt
                FROM tally_expected e JOIN item i ON i.id = e.item_id JOIN category c ON c.id = i.category_id
                WHERE e.session_id = ? GROUP BY c.code, c.name ORDER BY c.code""", id));
        BigDecimal missingWt = missing.stream().map(m -> Num.of(m.get("net_wt"))).reduce(Num.ZERO, BigDecimal::add);
        s.put("missing_wt", Num.r(missingWt));
        s.put("variances", db.rows("""
                SELECT v.*, i.tag_code, i.name FROM tally_variance v LEFT JOIN item i ON i.id = v.item_id
                WHERE v.session_id = ? ORDER BY v.kind, v.id""", id));
        // Customer repair pieces are counted as their own bucket, never as sale stock (FR-TAL-02).
        s.put("repair_bucket", db.value("SELECT COUNT(*) FROM repair_job WHERE status IN ('RECEIVED','IN_PROGRESS','READY')", Long.class));
        s.put("karigar_bucket", db.value("SELECT COUNT(*) FROM repair_job WHERE status = 'WITH_KARIGAR'", Long.class));
        s.put("recent_scans", db.rows("""
                SELECT s.code, s.scanned_at, i.name FROM tally_scan s LEFT JOIN item i ON i.id = s.item_id
                WHERE s.session_id = ? ORDER BY s.id DESC LIMIT 15""", id));
        return s;
    }

    /** Builds the variance list for review: one row per missing, unexpected or unknown tag. */
    @Transactional
    public Map<String, Object> compare(long id) {
        CurrentUser.require(Permission.TALLY_CAPTURE);
        requireOpen(id);
        Map<String, Object> s = summary(id);
        db.update("DELETE FROM tally_variance WHERE session_id = ? AND resolution IS NULL", id);
        addVariances(id, "MISSING", s.get("missing"));
        addVariances(id, "UNEXPECTED", s.get("unexpected"));
        for (Object o : (List<?>) s.get("unknown")) {
            String code = str(((Map<?, ?>) o).get("code"));
            if (db.opt("SELECT id FROM tally_variance WHERE session_id = ? AND kind = 'UNKNOWN' AND code = ?", id, code).isEmpty()) {
                db.update("INSERT INTO tally_variance (session_id, kind, code) VALUES (?, 'UNKNOWN', ?)", id, code);
            }
        }
        return summary(id);
    }

    private void addVariances(long id, String kind, Object rows) {
        for (Object o : (List<?>) rows) {
            Map<?, ?> r = (Map<?, ?>) o;
            long itemId = Rows.id(r.get("id"));
            if (db.opt("SELECT id FROM tally_variance WHERE session_id = ? AND item_id = ? AND kind = ?", id, itemId, kind).isEmpty()) {
                db.update("INSERT INTO tally_variance (session_id, kind, item_id, code) VALUES (?,?,?,?)",
                        id, kind, itemId, r.get("tag_code"));
            }
        }
    }

    /**
     * Manager decision on one variance. MARK_LOST posts a tally-loss movement;
     * ACCEPTED keeps stock as it is with the reason on record.
     */
    @Transactional
    public Map<String, Object> resolve(long varianceId, String resolution, String reason) {
        CurrentUser.require(Permission.TALLY_APPROVE);
        Map<String, Object> v = db.one("SELECT * FROM tally_variance WHERE id = ?", "Variance not found", varianceId);
        long sessionId = Rows.id(v.get("session_id"));
        requireOpen(sessionId);
        String res = str(resolution).toUpperCase();
        if (str(reason).isEmpty()) throw ApiException.bad("Give a reason.");
        if (res.equals("MARK_LOST")) {
            if (!"MISSING".equals(v.get("kind"))) throw ApiException.bad("Only a missing item can be marked lost.");
            stock.post(new StockLedger.Move(Rows.id(v.get("item_id")), "TALLY_LOSS", -1, "IN_STOCK", "LOST", null,
                    "TALLY", sessionId, reason));
        } else if (!res.equals("ACCEPTED")) {
            throw ApiException.bad("Resolution must be MARK_LOST or ACCEPTED.");
        }
        db.update("UPDATE tally_variance SET resolution = ?, reason = ?, resolved_by = ?, resolved_at = ? WHERE id = ?",
                res, reason, CurrentUser.usernameOrSystem(), Timestamp.from(Instant.now()), varianceId);
        audit.log("TALLY_RESOLVE", "tally", sessionId, v.get("kind") + " " + v.get("code") + " -> " + res + ": " + reason);
        return summary(sessionId);
    }

    @Transactional
    public Map<String, Object> close(long id) {
        CurrentUser.require(Permission.TALLY_APPROVE);
        compare(id);
        long open = db.value("SELECT COUNT(*) FROM tally_variance WHERE session_id = ? AND resolution IS NULL", Long.class, id);
        if (open > 0 && config.flag("tally.strictClose", true)) {
            throw ApiException.conflict(open + " variance(s) still need a decision before the tally can be closed.");
        }
        db.update("UPDATE tally_session SET status = 'CLOSED', closed_by = ?, closed_at = ? WHERE id = ?",
                CurrentUser.usernameOrSystem(), Timestamp.from(Instant.now()), id);
        audit.log("TALLY_CLOSE", "tally", id, "open variances " + open);
        return summary(id);
    }

    @Transactional
    public Map<String, Object> reopen(long id, String reason) {
        CurrentUser.require(Permission.TALLY_APPROVE);
        if (str(reason).isEmpty()) throw ApiException.bad("Give a reason to reopen.");
        Map<String, Object> s = db.one("SELECT * FROM tally_session WHERE id = ?", "Tally session not found", id);
        if (!"CLOSED".equals(s.get("status"))) throw ApiException.conflict("Only a closed tally can be reopened.");
        db.update("UPDATE tally_session SET status = 'OPEN', closed_by = NULL, closed_at = NULL WHERE id = ?", id);
        audit.log("TALLY_REOPEN", "tally", id, reason);
        return summary(id);
    }

    public List<Map<String, Object>> list() {
        return db.rows("""
                SELECT t.*, l.name AS location_name, c.name AS category_name,
                       (SELECT COUNT(*) FROM tally_scan s WHERE s.session_id = t.id) AS scanned_count,
                       (SELECT COUNT(*) FROM tally_variance v WHERE v.session_id = t.id) AS variance_count
                FROM tally_session t LEFT JOIN location l ON l.id = t.location_id LEFT JOIN category c ON c.id = t.category_id
                ORDER BY t.id DESC LIMIT 100""");
    }

    private void requireOpen(long id) {
        Map<String, Object> s = db.one("SELECT status FROM tally_session WHERE id = ?", "Tally session not found", id);
        if (!"OPEN".equals(s.get("status"))) throw ApiException.conflict("This tally is closed.");
    }

    static List<String> splitCodes(String text) {
        List<String> out = new ArrayList<>();
        for (String c : text.split("[\\s,;]+")) if (!c.isBlank()) out.add(c);
        return out;
    }
}
