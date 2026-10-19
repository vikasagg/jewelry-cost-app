package com.swarnos.repair.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.repair.domain.RepairEvent;
import com.swarnos.repair.domain.RepairJob;
import com.swarnos.repair.domain.RepairJobView;
import com.swarnos.repair.domain.RepairStats;
import com.swarnos.repair.domain.RepairStatus;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class RepairRepository {
    private static final RowMapper<RepairJob> JOB = (rs, i) -> new RepairJob(rs.getLong("id"), rs.getString("job_no"),
            rs.getLong("customer_id"), rs.getString("description"), Columns.enumOrNull(rs, "metal", Metal.class),
            rs.getString("purity_code"), Columns.decimalOrZero(rs, "weight_in"), rs.getString("item_condition"),
            rs.getString("repair_type"), Columns.decimalOrZero(rs, "estimate"), Columns.date(rs, "promised_date"),
            RepairStatus.valueOf(rs.getString("status")), Columns.longOrNull(rs, "karigar_id"), Columns.decimal(rs, "weight_issued"),
            Columns.decimal(rs, "weight_returned"), Columns.decimalOrZero(rs, "extra_metal_wt"), Columns.decimal(rs, "weight_out"),
            Columns.decimal(rs, "charges"), Columns.decimalOrZero(rs, "paid"), rs.getString("created_by"),
            Columns.instant(rs, "created_at"), Columns.instant(rs, "delivered_at"));
    private static final String VIEW = """
            SELECT r.*, c.name AS customer_name, c.phone AS customer_phone, k.name AS karigar_name
            FROM repair_job r JOIN party c ON c.id = r.customer_id LEFT JOIN party k ON k.id = r.karigar_id""";
    private static final RowMapper<RepairJobView> VIEW_MAPPER = (rs, i) -> new RepairJobView(JOB.mapRow(rs, i),
            rs.getString("customer_name"), rs.getString("customer_phone"), rs.getString("karigar_name"));
    private static final RowMapper<RepairEvent> EVENT = (rs, i) -> new RepairEvent(rs.getLong("id"), rs.getLong("job_id"),
            RepairStatus.valueOf(rs.getString("status")), Columns.decimal(rs, "weight"), rs.getString("note"),
            rs.getString("username"), Columns.instant(rs, "at"));

    private final SqlSupport sql;

    public RepairRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public long insert(RepairJob j) {
        return sql.insert("""
                INSERT INTO repair_job (job_no, customer_id, description, metal, purity_code, weight_in, item_condition,
                    repair_type, estimate, promised_date, status, created_by)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""", j.jobNo(), j.customerId(), j.description(), Columns.name(j.metal()),
                j.purityCode(), j.weightIn(), j.itemCondition(), j.repairType(), j.estimate(), j.promisedDate(), j.status().name(),
                j.createdBy());
    }

    public Optional<RepairJobView> findView(long id) {
        return sql.one(VIEW + " WHERE r.id = ?", VIEW_MAPPER, id);
    }

    public Optional<Long> findIdByNumber(String jobNo) {
        return sql.one("SELECT id FROM repair_job WHERE UPPER(job_no) = UPPER(?)", (rs, i) -> rs.getLong("id"), jobNo);
    }

    /** filter: null = all, "OPEN" = not delivered, otherwise a status name. */
    public List<RepairJobView> list(String filter, String text) {
        String f = filter == null ? "" : filter;
        String like = "%" + (text == null ? "" : text.trim().toLowerCase()) + "%";
        return sql.list(VIEW + """
                 WHERE (? = '' OR r.status = ? OR (? = 'OPEN' AND r.status <> 'DELIVERED'))
                  AND (LOWER(r.job_no) LIKE ? OR LOWER(c.name) LIKE ? OR COALESCE(c.phone, '') LIKE ?)
                ORDER BY r.id DESC LIMIT 300""", VIEW_MAPPER, f, f, f, like, like, like);
    }

    public List<RepairJob> findByParty(long partyId) {
        return sql.list("SELECT * FROM repair_job WHERE customer_id = ? OR karigar_id = ? ORDER BY id DESC", JOB, partyId, partyId);
    }

    public void updateStatus(long id, RepairStatus status) {
        sql.update("UPDATE repair_job SET status = ? WHERE id = ?", status.name(), id);
    }

    public void issueToKarigar(long id, long karigarId, BigDecimal weight) {
        sql.update("UPDATE repair_job SET karigar_id = ?, weight_issued = ? WHERE id = ?", karigarId, weight, id);
    }

    public void recordReturnFromKarigar(long id, BigDecimal weight) {
        sql.update("UPDATE repair_job SET weight_returned = ? WHERE id = ?", weight, id);
    }

    public void recordFinished(long id, BigDecimal weightOut, BigDecimal extraMetal) {
        sql.update("UPDATE repair_job SET weight_out = ?, extra_metal_wt = ? WHERE id = ?", weightOut, extraMetal, id);
    }

    public void recordPaid(long id, BigDecimal paid) {
        sql.update("UPDATE repair_job SET paid = ? WHERE id = ?", paid, id);
    }

    public void recordDelivered(long id, BigDecimal charges, BigDecimal paid, Instant at) {
        sql.update("UPDATE repair_job SET charges = ?, paid = ?, delivered_at = ? WHERE id = ?", charges, paid, Columns.timestamp(at), id);
    }

    public void insertEvent(long jobId, RepairStatus status, BigDecimal weight, String note, String username) {
        sql.update("INSERT INTO repair_event (job_id, status, weight, note, username) VALUES (?,?,?,?,?)",
                jobId, status.name(), weight, note, username);
    }

    public List<RepairEvent> findEvents(long jobId) {
        return sql.list("SELECT * FROM repair_event WHERE job_id = ? ORDER BY id", EVENT, jobId);
    }

    public RepairStats stats(LocalDate today) {
        return sql.one("""
                SELECT COALESCE(SUM(CASE WHEN status <> 'DELIVERED' THEN 1 ELSE 0 END), 0) AS open_jobs,
                       COALESCE(SUM(CASE WHEN status = 'READY' THEN 1 ELSE 0 END), 0) AS ready,
                       COALESCE(SUM(CASE WHEN status <> 'DELIVERED' AND promised_date < ? THEN 1 ELSE 0 END), 0) AS overdue
                FROM repair_job""", (rs, i) -> new RepairStats(rs.getLong("open_jobs"), rs.getLong("ready"), rs.getLong("overdue")),
                today).orElseThrow();
    }

    public long countIn(List<RepairStatus> statuses) {
        String in = String.join(",", java.util.Collections.nCopies(statuses.size(), "?"));
        return sql.scalar("SELECT COUNT(*) FROM repair_job WHERE status IN (" + in + ")", Long.class,
                statuses.stream().map(Enum::name).toArray());
    }
}
