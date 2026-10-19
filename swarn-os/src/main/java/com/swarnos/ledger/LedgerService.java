package com.swarnos.ledger;

import com.swarnos.auth.CurrentUser;
import com.swarnos.common.ApiException;
import com.swarnos.common.BusinessClock;
import com.swarnos.common.Db;
import com.swarnos.common.Num;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;

/**
 * Books (BRD §5.1, §8): CASH and BANK in rupees, GOLD / SILVER / PLATINUM in
 * fine grams, PARTY in rupees (debit = the party owes the shop). Debit is
 * always "in" for cash, bank and metal books.
 */
@Service
public class LedgerService {
    public static final List<String> BOOKS = List.of("CASH", "BANK", "GOLD", "SILVER", "PLATINUM");

    private final Db db;
    private final BusinessClock clock;

    public LedgerService(Db db, BusinessClock clock) {
        this.db = db;
        this.clock = clock;
    }

    public void post(String book, Long partyId, String docType, long docId, BigDecimal debit, BigDecimal credit,
                     String narration) {
        BigDecimal d = Num.r(debit), c = Num.r(credit);
        if (d.signum() == 0 && c.signum() == 0) return;
        db.update("""
                INSERT INTO ledger_entry (book, business_date, party_id, doc_type, doc_id, debit, credit, narration)
                VALUES (?,?,?,?,?,?,?,?)""", book, clock.today(), partyId, docType, docId, d, c, narration);
    }

    public static String bookForMode(String mode) {
        return switch (mode) {
            case "CASH" -> "CASH";
            case "UPI", "CARD", "BANK", "CHEQUE" -> "BANK";
            default -> throw ApiException.bad("Unknown payment mode: " + mode);
        };
    }

    /** Records money received (IN) or paid (OUT) against a document, with its cash/bank and party postings. */
    public void payment(String docType, long docId, Long partyId, String direction, String mode, BigDecimal amount,
                        String reference, String narration) {
        BigDecimal amt = Num.r(amount);
        if (amt.signum() == 0) return;
        if (amt.signum() < 0) throw ApiException.bad("Payment amount cannot be negative.");
        String book = bookForMode(mode);
        db.update("""
                INSERT INTO payment (doc_type, doc_id, party_id, direction, mode, amount, reference, business_date, created_by)
                VALUES (?,?,?,?,?,?,?,?,?)""", docType, docId, partyId, direction, mode, amt, reference, clock.today(),
                CurrentUser.usernameOrSystem());
        boolean in = direction.equals("IN");
        post(book, partyId, docType, docId, in ? amt : Num.ZERO, in ? Num.ZERO : amt,
                narration + " (" + mode + (reference == null || reference.isBlank() ? "" : " " + reference) + ")");
        if (partyId != null) post("PARTY", partyId, docType, docId, in ? Num.ZERO : amt, in ? amt : Num.ZERO, narration);
    }

    public BigDecimal balance(String book) {
        return Num.r(db.value("SELECT COALESCE(SUM(debit - credit), 0) FROM ledger_entry WHERE book = ?", BigDecimal.class, book));
    }

    public BigDecimal partyBalance(long partyId) {
        return Num.r(db.value("SELECT COALESCE(SUM(debit - credit), 0) FROM ledger_entry WHERE book = 'PARTY' AND party_id = ?",
                BigDecimal.class, partyId));
    }

    /** Day book of one ledger with opening and running balance. */
    public Map<String, Object> book(String book, LocalDate from, LocalDate to) {
        BigDecimal opening = Num.r(db.value("SELECT COALESCE(SUM(debit - credit), 0) FROM ledger_entry WHERE book = ? AND business_date < ?",
                BigDecimal.class, book, from));
        List<Map<String, Object>> rows = db.rows("""
                SELECT e.*, p.name AS party_name FROM ledger_entry e LEFT JOIN party p ON p.id = e.party_id
                WHERE e.book = ? AND e.business_date BETWEEN ? AND ? ORDER BY e.business_date, e.id""", book, from, to);
        BigDecimal running = opening;
        List<Map<String, Object>> out = new ArrayList<>();
        BigDecimal debit = Num.ZERO, credit = Num.ZERO;
        for (Map<String, Object> r : rows) {
            Map<String, Object> row = new LinkedHashMap<>(r);
            debit = debit.add((BigDecimal) r.get("debit"));
            credit = credit.add((BigDecimal) r.get("credit"));
            running = running.add((BigDecimal) r.get("debit")).subtract((BigDecimal) r.get("credit"));
            row.put("balance", Num.r(running));
            out.add(row);
        }
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("book", book);
        res.put("from", from.toString());
        res.put("to", to.toString());
        res.put("opening", opening);
        res.put("total_debit", Num.r(debit));
        res.put("total_credit", Num.r(credit));
        res.put("closing", Num.r(running));
        res.put("entries", out);
        return res;
    }
}
