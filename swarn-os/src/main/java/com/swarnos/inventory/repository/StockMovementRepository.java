package com.swarnos.inventory.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.inventory.domain.ItemStatus;
import com.swarnos.inventory.domain.MovementType;
import com.swarnos.inventory.domain.StockMovement;
import java.util.List;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class StockMovementRepository {
    private static final RowMapper<StockMovement> MAPPER = (rs, i) -> new StockMovement(rs.getLong("id"), rs.getLong("item_id"),
            MovementType.valueOf(rs.getString("movement_type")), rs.getInt("qty"), Columns.decimalOrZero(rs, "gross_wt"),
            Columns.decimalOrZero(rs, "net_wt"), ItemStatus.valueOf(rs.getString("status_after")), rs.getString("doc_type"),
            Columns.longOrNull(rs, "doc_id"), Columns.date(rs, "business_date"), rs.getString("username"),
            Columns.instant(rs, "created_at"), rs.getString("idem_key"), rs.getString("note"));

    private final SqlSupport sql;

    public StockMovementRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public void insert(StockMovement m) {
        sql.update("""
                INSERT INTO stock_movement (item_id, movement_type, qty, gross_wt, net_wt, status_after, doc_type, doc_id,
                                            business_date, username, idem_key, note)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""", m.itemId(), m.movementType().name(), m.qty(), m.grossWt(), m.netWt(),
                m.statusAfter().name(), m.docType(), m.docId(), m.businessDate(), m.username(), m.idemKey(), m.note());
    }

    public List<StockMovement> findByItem(long itemId) {
        return sql.list("SELECT * FROM stock_movement WHERE item_id = ? ORDER BY id", MAPPER, itemId);
    }
}
