package com.swarnos.repair;

import static com.swarnos.common.Rows.str;
import static com.swarnos.common.Rows.strOrNull;

import com.swarnos.auth.CurrentUser;
import com.swarnos.auth.Permission;
import com.swarnos.common.ApiException;
import com.swarnos.common.AuditService;
import com.swarnos.common.BusinessClock;
import com.swarnos.common.Db;
import com.swarnos.common.DocNumbers;
import com.swarnos.common.Num;
import com.swarnos.common.Rows;
import com.swarnos.config.ConfigService;
import com.swarnos.ledger.LedgerService;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Repair and job-work (BRD §11). The customer's piece is held in repair
 * custody, never in sale stock; every hand-off records weight so metal loss
 * or gain is visible at delivery.
 */
@Service
public class RepairService {
    private static final Map<String, Set<String>> NEXT = Map.of(
            "RECEIVED", Set.of("WITH_KARIGAR", "IN_PROGRESS", "READY"),
            "WITH_KARIGAR", Set.of("READY", "IN_PROGRESS"),
            "IN_PROGRESS", Set.of("READY", "WITH_KARIGAR"),
            "READY", Set.of("DELIVERED", "IN_PROGRESS"),
            "DELIVERED", Set.of());

    private final Db db;
    private final LedgerService ledgers;
    private final DocNumbers numbers;
    private final ConfigService config;
    private final AuditService audit;
    private final BusinessClock clock;

    public RepairService(Db db, LedgerService ledgers, DocNumbers numbers, ConfigService config, AuditService audit,
                         BusinessClock clock) {
        this.db = db;
        this.ledgers = ledgers;
        this.numbers = numbers;
        this.config = config;
        this.audit = audit;
        this.clock = clock;
    }

    @Transactional
    public Map<String, Object> intake(Map<String, Object> b) {
        CurrentUser.require(Permission.REPAIR);
        long customer = Rows.id(b.get("customer_id"));
        db.one("SELECT id FROM party WHERE id = ?", "Customer not found", customer);
        BigDecimal weightIn = Num.of(b.get("weight_in"));
        if (!Num.positive(weightIn)) throw ApiException.bad("Weigh the piece: weight in is required.");
        if (str(b.get("description")).isEmpty()) throw ApiException.bad("Describe the piece.");
        String no = numbers.next(config.get("repair.prefix", "REP"), clock.today());
        long id = db.insert("""
                INSERT INTO repair_job (job_no, customer_id, description, metal, purity_code, weight_in, item_condition,
                    repair_type, estimate, promised_date, status, created_by)
                VALUES (?,?,?,?,?,?,?,?,?,?, 'RECEIVED', ?)""", no, customer, str(b.get("description")),
                strOrNull(b.get("metal")), strOrNull(b.get("purity_code")), weightIn, strOrNull(b.get("item_condition")),
                strOrNull(b.get("repair_type")), Num.of(b.get("estimate")), Rows.date(b.get("promised_date")),
                CurrentUser.usernameOrSystem());
        event(id, "RECEIVED", weightIn, "Received from customer");
        BigDecimal advance = Num.of(b.get("advance"));
        if (advance.signum() > 0) {
            ledgers.payment("REPAIR", id, customer, "IN", str(b.get("advance_mode")).isEmpty() ? "CASH" : str(b.get("advance_mode")).toUpperCase(),
                    advance, null, "Repair advance " + no);
            db.update("UPDATE repair_job SET paid = ? WHERE id = ?", advance, id);
        }
        audit.log("REPAIR_INTAKE", "repair", no, "weight in " + weightIn);
        return get(id);
    }

    /** Moves the job to its next step, recording the weight at each hand-off. */
    @Transactional
    public Map<String, Object> advance(long id, Map<String, Object> b) {
        CurrentUser.require(Permission.REPAIR);
        Map<String, Object> job = db.one("SELECT * FROM repair_job WHERE id = ?", "Repair job not found", id);
        String from = (String) job.get("status");
        String to = str(b.get("status")).toUpperCase();
        if (!NEXT.getOrDefault(from, Set.of()).contains(to)) {
            throw ApiException.conflict("A job that is " + from + " cannot move to " + to + ".");
        }
        BigDecimal weight = Num.ofNullable(b.get("weight"));
        String note = strOrNull(b.get("note"));
        switch (to) {
            case "WITH_KARIGAR" -> {
                long karigar = Rows.id(b.get("karigar_id"));
                db.one("SELECT id FROM party WHERE id = ? AND party_type = 'KARIGAR'", "Choose a karigar", karigar);
                if (weight == null) throw ApiException.bad("Weigh the piece before giving it to the karigar.");
                db.update("UPDATE repair_job SET karigar_id = ?, weight_issued = ? WHERE id = ?", karigar, weight, id);
            }
            case "READY" -> {
                if (weight == null) throw ApiException.bad("Weigh the finished piece.");
                if ("WITH_KARIGAR".equals(from)) db.update("UPDATE repair_job SET weight_returned = ? WHERE id = ?", weight, id);
                db.update("UPDATE repair_job SET weight_out = ?, extra_metal_wt = ? WHERE id = ?", weight,
                        Num.of(b.get("extra_metal_wt")), id);
            }
            case "DELIVERED" -> deliver(job, b);
            default -> { }
        }
        db.update("UPDATE repair_job SET status = ? WHERE id = ?", to, id);
        event(id, to, weight, note);
        audit.log("REPAIR_" + to, "repair", job.get("job_no"), weight == null ? null : "weight " + weight);
        return get(id);
    }

    private void deliver(Map<String, Object> job, Map<String, Object> b) {
        long id = Rows.id(job);
        long customer = Rows.id(job.get("customer_id"));
        BigDecimal charges = Num.of(b.get("charges"));
        BigDecimal pay = Num.of(b.get("amount"));
        BigDecimal paidBefore = Num.of(job.get("paid"));
        if (paidBefore.add(pay).compareTo(charges) > 0) throw ApiException.bad("Payment is more than the charges.");
        db.update("UPDATE repair_job SET charges = ?, paid = ?, delivered_at = ? WHERE id = ?", charges,
                Num.r(paidBefore.add(pay)), Timestamp.from(Instant.now()), id);
        ledgers.post("PARTY", customer, "REPAIR", id, charges, Num.ZERO, "Repair " + job.get("job_no"));
        ledgers.payment("REPAIR", id, customer, "IN", str(b.get("mode")).isEmpty() ? "CASH" : str(b.get("mode")).toUpperCase(),
                pay, strOrNull(b.get("reference")), "Repair " + job.get("job_no"));
    }

    private void event(long id, String status, BigDecimal weight, String note) {
        db.update("INSERT INTO repair_event (job_id, status, weight, note, username) VALUES (?,?,?,?,?)",
                id, status, weight, note, CurrentUser.usernameOrSystem());
    }

    public Map<String, Object> get(long id) {
        Map<String, Object> j = new LinkedHashMap<>(db.one("""
                SELECT r.*, c.name AS customer_name, c.phone AS customer_phone, k.name AS karigar_name
                FROM repair_job r JOIN party c ON c.id = r.customer_id LEFT JOIN party k ON k.id = r.karigar_id
                WHERE r.id = ?""", "Repair job not found", id));
        j.put("events", db.rows("SELECT * FROM repair_event WHERE job_id = ? ORDER BY id", id));
        if (j.get("weight_out") != null) {
            j.put("metal_difference", Num.r(Num.of(j.get("weight_out")).subtract(Num.of(j.get("weight_in")))));
        }
        if (j.get("weight_returned") != null && j.get("weight_issued") != null) {
            j.put("karigar_difference", Num.r(Num.of(j.get("weight_returned")).subtract(Num.of(j.get("weight_issued")))));
        }
        return j;
    }

    public Map<String, Object> byNo(String no) {
        Map<String, Object> r = db.one("SELECT id FROM repair_job WHERE UPPER(job_no) = UPPER(?)", "No repair job " + no, no.trim());
        return get(Rows.id(r));
    }

    public List<Map<String, Object>> list(String status, String q) {
        String like = "%" + (q == null ? "" : q.trim().toLowerCase()) + "%";
        return db.rows("""
                SELECT r.*, c.name AS customer_name, c.phone AS customer_phone, k.name AS karigar_name,
                       CASE WHEN r.status <> 'DELIVERED' AND r.promised_date < ? THEN TRUE ELSE FALSE END AS overdue
                FROM repair_job r JOIN party c ON c.id = r.customer_id LEFT JOIN party k ON k.id = r.karigar_id
                WHERE (? = '' OR r.status = ? OR (? = 'OPEN' AND r.status <> 'DELIVERED'))
                  AND (LOWER(r.job_no) LIKE ? OR LOWER(c.name) LIKE ? OR COALESCE(c.phone, '') LIKE ?)
                ORDER BY r.id DESC LIMIT 300""", clock.today(), status == null ? "" : status, status == null ? "" : status,
                status == null ? "" : status, like, like, like);
    }
}
