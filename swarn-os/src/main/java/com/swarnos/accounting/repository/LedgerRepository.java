package com.swarnos.accounting.repository;

import com.swarnos.accounting.domain.Book;
import com.swarnos.accounting.domain.DocumentType;
import com.swarnos.accounting.domain.LedgerEntry;
import com.swarnos.common.money.Decimals;
import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class LedgerRepository {
    private static final RowMapper<LedgerEntry> ENTRY = (rs, i) -> new LedgerEntry(rs.getLong("id"), Book.valueOf(rs.getString("book")),
            Columns.date(rs, "business_date"), Columns.longOrNull(rs, "party_id"), DocumentType.valueOf(rs.getString("doc_type")),
            rs.getLong("doc_id"), Columns.decimalOrZero(rs, "debit"), Columns.decimalOrZero(rs, "credit"), rs.getString("narration"),
            Columns.instant(rs, "created_at"));

    /** An entry with the party's name, for statements. */
    public record NamedEntry(LedgerEntry entry, String partyName) {}

    private final SqlSupport sql;

    public LedgerRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public void insert(Book book, LocalDate date, Long partyId, DocumentType docType, long docId, BigDecimal debit,
                       BigDecimal credit, String narration) {
        sql.update("""
                INSERT INTO ledger_entry (book, business_date, party_id, doc_type, doc_id, debit, credit, narration)
                VALUES (?,?,?,?,?,?,?,?)""", book.name(), date, partyId, docType.name(), docId, debit, credit, narration);
    }

    public BigDecimal balance(Book book) {
        return Decimals.orZero(sql.scalar("SELECT COALESCE(SUM(debit - credit), 0) FROM ledger_entry WHERE book = ?",
                BigDecimal.class, book.name()));
    }

    public BigDecimal balanceBefore(Book book, LocalDate date) {
        return Decimals.orZero(sql.scalar("SELECT COALESCE(SUM(debit - credit), 0) FROM ledger_entry WHERE book = ? AND business_date < ?",
                BigDecimal.class, book.name(), date));
    }

    public List<NamedEntry> entries(Book book, LocalDate from, LocalDate to) {
        return sql.list("""
                SELECT e.*, p.name AS party_name FROM ledger_entry e LEFT JOIN party p ON p.id = e.party_id
                WHERE e.book = ? AND e.business_date BETWEEN ? AND ? ORDER BY e.business_date, e.id""",
                (rs, i) -> new NamedEntry(ENTRY.mapRow(rs, i), rs.getString("party_name")), book.name(), from, to);
    }

    public BigDecimal partyBalance(long partyId) {
        return Decimals.orZero(sql.scalar("SELECT COALESCE(SUM(debit - credit), 0) FROM ledger_entry WHERE book = 'PARTY' AND party_id = ?",
                BigDecimal.class, partyId));
    }

    public Map<Long, BigDecimal> partyBalances() {
        Map<Long, BigDecimal> out = new HashMap<>();
        sql.list("SELECT party_id, SUM(debit - credit) AS balance FROM ledger_entry WHERE book = 'PARTY' GROUP BY party_id",
                (rs, i) -> out.put(rs.getLong("party_id"), Columns.decimalOrZero(rs, "balance")));
        return out;
    }

    public List<LedgerEntry> partyEntries(long partyId) {
        return sql.list("SELECT * FROM ledger_entry WHERE book = 'PARTY' AND party_id = ? ORDER BY id", ENTRY, partyId);
    }
}
