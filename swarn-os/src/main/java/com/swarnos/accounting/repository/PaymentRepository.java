package com.swarnos.accounting.repository;

import com.swarnos.accounting.domain.Direction;
import com.swarnos.accounting.domain.DocumentType;
import com.swarnos.accounting.domain.Payment;
import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import java.util.List;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class PaymentRepository {
    private static final RowMapper<Payment> MAPPER = (rs, i) -> new Payment(rs.getLong("id"), DocumentType.valueOf(rs.getString("doc_type")),
            rs.getLong("doc_id"), Columns.longOrNull(rs, "party_id"), Direction.valueOf(rs.getString("direction")),
            PaymentMode.valueOf(rs.getString("mode")), Columns.decimalOrZero(rs, "amount"), rs.getString("reference"),
            Columns.date(rs, "business_date"), rs.getString("created_by"), Columns.instant(rs, "created_at"));

    private final SqlSupport sql;

    public PaymentRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public void insert(Payment p) {
        sql.update("""
                INSERT INTO payment (doc_type, doc_id, party_id, direction, mode, amount, reference, business_date, created_by)
                VALUES (?,?,?,?,?,?,?,?,?)""", p.docType().name(), p.docId(), p.partyId(), p.direction().name(), p.mode().name(),
                p.amount(), p.reference(), p.businessDate(), p.createdBy());
    }

    public List<Payment> forDocument(long docId, DocumentType... types) {
        String in = String.join(",", java.util.Collections.nCopies(types.length, "?"));
        Object[] args = new Object[types.length + 1];
        for (int i = 0; i < types.length; i++) args[i] = types[i].name();
        args[types.length] = docId;
        return sql.list("SELECT * FROM payment WHERE doc_type IN (" + in + ") AND doc_id = ? ORDER BY id", MAPPER, args);
    }
}
