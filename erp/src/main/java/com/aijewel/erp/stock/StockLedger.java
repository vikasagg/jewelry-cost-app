package com.aijewel.erp.stock;

import com.aijewel.erp.auth.CurrentUser;
import com.aijewel.erp.common.ApiException;
import com.aijewel.erp.common.BusinessClock;
import com.aijewel.erp.common.Db;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;

/**
 * The only place that changes stock. Every change is a movement row; the
 * item's status and location are a cache updated in the same transaction
 * (BRD FR-STK-01..04). Callers run inside their document's transaction.
 */
@Service
public class StockLedger {
    private final Db db;
    private final BusinessClock clock;

    public StockLedger(Db db, BusinessClock clock) {
        this.db = db;
        this.clock = clock;
    }

    public record Move(long itemId, String type, int qty, String requiredStatus, String statusAfter,
                       Long toLocationId, String docType, Long docId, String note) {}

    public void post(Move m) {
        Map<String, Object> item = db.one("SELECT * FROM item WHERE id = ?", "Item not found", m.itemId());
        String status = (String) item.get("status");
        if (m.requiredStatus() != null && !Set.of(m.requiredStatus().split("\\|")).contains(status)) {
            throw ApiException.conflict("Tag " + item.get("tag_code") + " is " + status.replace('_', ' ').toLowerCase()
                    + " and cannot be used here.");
        }
        String key = m.type() + ":" + (m.docType() == null ? "-" : m.docType()) + ":"
                + (m.docId() == null ? System.nanoTime() : m.docId()) + ":" + m.itemId();
        db.update("""
                INSERT INTO stock_movement (item_id, movement_type, qty, gross_wt, net_wt, status_after, doc_type,
                                            doc_id, business_date, username, idem_key, note)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
                m.itemId(), m.type(), m.qty(), item.get("gross_wt"), item.get("net_wt"), m.statusAfter(),
                m.docType(), m.docId(), clock.today(), CurrentUser.usernameOrSystem(), key, m.note());
        if (m.toLocationId() != null) {
            db.update("UPDATE item SET status = ?, location_id = ? WHERE id = ?", m.statusAfter(), m.toLocationId(), m.itemId());
        } else {
            db.update("UPDATE item SET status = ? WHERE id = ?", m.statusAfter(), m.itemId());
        }
    }

    /**
     * Rebuilds each item's status from its last movement and lists any item
     * whose cached status disagrees with the ledger (scheduled check, FR-STK-01).
     */
    public java.util.List<Map<String, Object>> verify() {
        return db.rows("""
                SELECT i.id, i.tag_code, i.status AS cached_status, m.status_after AS ledger_status
                FROM item i
                LEFT JOIN stock_movement m ON m.id = (SELECT MAX(id) FROM stock_movement WHERE item_id = i.id)
                WHERE m.status_after IS NULL OR m.status_after <> i.status""");
    }
}
