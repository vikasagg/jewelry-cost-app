package com.swarnos.rates.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.rates.domain.RateLine;
import com.swarnos.rates.domain.RateSet;
import com.swarnos.rates.domain.RateSetStatus;
import com.swarnos.rates.domain.RateSource;
import com.swarnos.settings.domain.Metal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class RateRepository {
    private static final RowMapper<RateSet> SET = (rs, i) -> new RateSet(rs.getLong("id"), Columns.date(rs, "business_date"),
            RateSource.valueOf(rs.getString("source")), rs.getString("provider"), Columns.decimal(rs, "gold_24k"),
            Columns.decimal(rs, "silver_base"), Columns.decimal(rs, "platinum_base"), RateSetStatus.valueOf(rs.getString("status")),
            rs.getString("entered_by"), Columns.instant(rs, "entered_at"), rs.getString("approved_by"),
            Columns.instant(rs, "approved_at"), rs.getString("note"));
    private static final RowMapper<RateLine> LINE = (rs, i) -> new RateLine(Metal.valueOf(rs.getString("metal")),
            rs.getString("purity_code"), Columns.decimal(rs, "rate_per_gram"), null);

    private final SqlSupport sql;

    public RateRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public long insert(RateSet s) {
        return sql.insert("""
                INSERT INTO rate_set (business_date, source, provider, gold_24k, silver_base, platinum_base, status, entered_by, note)
                VALUES (?,?,?,?,?,?,?,?,?)""", s.businessDate(), s.source().name(), s.provider(), s.gold24k(), s.silverBase(),
                s.platinumBase(), s.status().name(), s.enteredBy(), s.note());
    }

    public void replaceLines(long rateSetId, List<RateLine> lines) {
        sql.update("DELETE FROM rate_line WHERE rate_set_id = ?", rateSetId);
        for (RateLine l : lines) {
            sql.update("INSERT INTO rate_line (rate_set_id, metal, purity_code, rate_per_gram) VALUES (?,?,?,?)",
                    rateSetId, l.metal().name(), l.purityCode(), l.ratePerGram());
        }
    }

    public Optional<RateSet> findById(long id) {
        return sql.one("SELECT * FROM rate_set WHERE id = ?", SET, id);
    }

    public List<RateLine> findLines(long rateSetId) {
        return sql.list("SELECT * FROM rate_line WHERE rate_set_id = ? ORDER BY id", LINE, rateSetId);
    }

    public Optional<RateSet> findApproved(LocalDate date) {
        return sql.one("SELECT * FROM rate_set WHERE business_date = ? AND status = 'APPROVED' ORDER BY id DESC LIMIT 1", SET, date);
    }

    public List<RateSet> findPending(LocalDate date) {
        return sql.list("SELECT * FROM rate_set WHERE business_date = ? AND status = 'PROPOSED' ORDER BY id DESC", SET, date);
    }

    public Optional<RateSet> findLastApproved() {
        return sql.one("SELECT * FROM rate_set WHERE status IN ('APPROVED','SUPERSEDED') ORDER BY id DESC LIMIT 1", SET);
    }

    public List<RateSet> history(int limit) {
        return sql.list("SELECT * FROM rate_set ORDER BY id DESC LIMIT " + limit, SET);
    }

    public List<RateSet> between(LocalDate from, LocalDate to) {
        return sql.list("SELECT * FROM rate_set WHERE business_date BETWEEN ? AND ? ORDER BY id DESC", SET, from, to);
    }

    public void supersedeApproved(LocalDate date) {
        sql.update("UPDATE rate_set SET status = 'SUPERSEDED' WHERE business_date = ? AND status = 'APPROVED'", date);
    }

    /** Changes a PROPOSED set to the given status; false when it was not proposed. */
    public boolean decide(long id, RateSetStatus status, String by, Instant at) {
        return sql.update("UPDATE rate_set SET status = ?, approved_by = ?, approved_at = ? WHERE id = ? AND status = 'PROPOSED'",
                status.name(), by, Columns.timestamp(at), id) > 0;
    }
}
