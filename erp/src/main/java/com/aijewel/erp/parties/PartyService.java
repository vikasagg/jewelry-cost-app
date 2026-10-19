package com.aijewel.erp.parties;

import static com.aijewel.erp.common.Rows.str;
import static com.aijewel.erp.common.Rows.strOrNull;

import com.aijewel.erp.auth.CurrentUser;
import com.aijewel.erp.auth.Permission;
import com.aijewel.erp.common.ApiException;
import com.aijewel.erp.common.AuditService;
import com.aijewel.erp.common.Db;
import com.aijewel.erp.common.Num;
import com.aijewel.erp.common.Rows;
import com.aijewel.erp.ledger.LedgerService;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Customers, vendors and karigars (BRD §10). */
@Service
public class PartyService {
    private static final Set<String> TYPES = Set.of("CUSTOMER", "VENDOR", "KARIGAR");

    private final Db db;
    private final LedgerService ledgers;
    private final AuditService audit;

    public PartyService(Db db, LedgerService ledgers, AuditService audit) {
        this.db = db;
        this.ledgers = ledgers;
        this.audit = audit;
    }

    public List<Map<String, Object>> list(String type, String q) {
        String like = "%" + (q == null ? "" : q.trim().toLowerCase()) + "%";
        return db.rows("""
                SELECT p.*, (SELECT COALESCE(SUM(debit - credit), 0) FROM ledger_entry e
                             WHERE e.book = 'PARTY' AND e.party_id = p.id) AS balance
                FROM party p
                WHERE (? = '' OR p.party_type = ?)
                  AND (LOWER(p.name) LIKE ? OR COALESCE(p.phone, '') LIKE ?)
                ORDER BY p.name LIMIT 300""", type == null ? "" : type, type == null ? "" : type, like, like);
    }

    public Map<String, Object> get(long id) {
        Map<String, Object> p = new LinkedHashMap<>(db.one("SELECT * FROM party WHERE id = ?", "Party not found", id));
        maskIds(p);
        p.put("balance", ledgers.partyBalance(id));
        // Permanent purchase history (FR-CUS-02): everything bought, returned, exchanged, repaired or sold to us.
        p.put("sales", db.rows("SELECT * FROM sale WHERE customer_id = ? ORDER BY id DESC", id));
        p.put("items_bought", db.rows("""
                SELECT s.invoice_no, s.business_date, s.status, l.description, l.purity_code, l.net_wt, l.rate,
                       l.line_total, i.tag_code
                FROM sale_line l JOIN sale s ON s.id = l.sale_id JOIN item i ON i.id = l.item_id
                WHERE s.customer_id = ? ORDER BY s.id DESC, l.id""", id));
        p.put("exchanges", db.rows("""
                SELECT s.invoice_no, s.business_date, x.* FROM sale_exchange x JOIN sale s ON s.id = x.sale_id
                WHERE s.customer_id = ? ORDER BY s.id DESC""", id));
        p.put("purchases", db.rows("SELECT * FROM purchase WHERE party_id = ? ORDER BY id DESC", id));
        p.put("repairs", db.rows("SELECT * FROM repair_job WHERE customer_id = ? OR karigar_id = ? ORDER BY id DESC", id, id));
        p.put("ledger", db.rows("SELECT * FROM ledger_entry WHERE book = 'PARTY' AND party_id = ? ORDER BY id", id));
        if (!CurrentUser.can(Permission.VIEW_PURCHASE_CLASS)) {
            ((List<?>) p.get("purchases")).forEach(r -> ((Map<?, ?>) r).remove("purchase_class"));
        }
        return p;
    }

    @Transactional
    public Map<String, Object> save(Map<String, Object> b) {
        CurrentUser.require(Permission.PARTY_EDIT);
        String type = str(b.get("party_type")).toUpperCase();
        if (!TYPES.contains(type)) throw ApiException.bad("Party type must be CUSTOMER, VENDOR or KARIGAR.");
        String name = str(b.get("name"));
        if (name.isEmpty()) throw ApiException.bad("Name is required.");
        String phone = strOrNull(b.get("phone"));
        Long id = Rows.idOrNull(b.get("id"));
        Object[] values = {type, name, phone, strOrNull(b.get("email")), strOrNull(b.get("address")),
                upper(b.get("gstin")), upper(b.get("pan")), strOrNull(b.get("id_proof")), Rows.date(b.get("birthday")),
                Rows.date(b.get("anniversary")), strOrNull(b.get("notes"))};
        if (id == null) {
            id = db.insert("""
                    INSERT INTO party (party_type, name, phone, email, address, gstin, pan, id_proof, birthday, anniversary, notes)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?)""", values);
            audit.log("PARTY_CREATE", "party", id, type + " " + name);
        } else {
            Object[] withId = java.util.Arrays.copyOf(values, values.length + 1);
            withId[values.length] = id;
            db.update("""
                    UPDATE party SET party_type = ?, name = ?, phone = ?, email = ?, address = ?, gstin = ?, pan = ?,
                        id_proof = ?, birthday = ?, anniversary = ?, notes = ? WHERE id = ?""", withId);
            audit.log("PARTY_UPDATE", "party", id, name);
        }
        return get(id);
    }

    /** Money received from or paid to a party outside a bill (settling dues). */
    @Transactional
    public Map<String, Object> settle(long id, Map<String, Object> b) {
        CurrentUser.require(Permission.PAYMENT);
        db.one("SELECT id FROM party WHERE id = ?", "Party not found", id);
        String direction = str(b.get("direction")).equalsIgnoreCase("OUT") ? "OUT" : "IN";
        ledgers.payment(direction.equals("IN") ? "RECEIPT" : "VOUCHER", id, id, direction, str(b.get("mode")).toUpperCase(),
                Num.of(b.get("amount")), strOrNull(b.get("reference")),
                direction.equals("IN") ? "Received from party" : "Paid to party");
        audit.log("PARTY_SETTLE", "party", id, direction + " " + b.get("amount"));
        return get(id);
    }

    private static String upper(Object o) {
        String s = strOrNull(o);
        return s == null ? null : s.toUpperCase();
    }

    private static void maskIds(Map<String, Object> p) {
        String idProof = (String) p.get("id_proof");
        if (idProof != null && idProof.length() > 4 && !CurrentUser.can(Permission.VIEW_COST)) {
            p.put("id_proof", "XXXX" + idProof.substring(idProof.length() - 4));
        }
    }
}
