package com.swarnos.purchase.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.inventory.domain.PurchaseClass;
import com.swarnos.purchase.domain.DayTotals;
import com.swarnos.purchase.domain.Purchase;
import com.swarnos.purchase.domain.PurchaseKind;
import com.swarnos.purchase.domain.PurchaseLine;
import com.swarnos.purchase.domain.PurchaseTotals;
import com.swarnos.purchase.domain.PurchaseView;
import com.swarnos.purchase.domain.SettlementMode;
import com.swarnos.purchase.domain.PaymentLegs;
import com.swarnos.settings.domain.Metal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class PurchaseRepository {
    static final RowMapper<Purchase> PURCHASE = (rs, i) -> new Purchase(rs.getLong("id"), rs.getString("purchase_no"),
            Columns.date(rs, "business_date"), Columns.longOrNull(rs, "party_id"), PurchaseKind.valueOf(rs.getString("purchase_kind")),
            SettlementMode.valueOf(rs.getString("payment_mode")), rs.getString("gst_invoice_no"),
            Columns.decimalOrZero(rs, "taxable_amount"), Columns.decimalOrZero(rs, "gst_amount"), Columns.decimalOrZero(rs, "total_amount"),
            Columns.decimalOrZero(rs, "cash_paid"), Columns.decimalOrZero(rs, "bank_paid"), rs.getString("bank_ref"),
            Columns.decimalOrZero(rs, "gold_fine_paid"), Columns.decimalOrZero(rs, "silver_fine_paid"),
            Columns.decimalOrZero(rs, "metal_value_paid"), Columns.decimalOrZero(rs, "balance_due"),
            PurchaseClass.valueOf(rs.getString("purchase_class")), Columns.longOrNull(rs, "rate_set_id"), rs.getString("notes"),
            rs.getString("created_by"), Columns.instant(rs, "created_at"));
    private static final RowMapper<PurchaseLine> LINE = (rs, i) -> new PurchaseLine(rs.getLong("id"), rs.getLong("purchase_id"),
            Columns.longOrNull(rs, "item_id"), rs.getString("description"), Columns.enumOrNull(rs, "metal", Metal.class),
            rs.getString("purity_code"), Columns.decimalOrZero(rs, "gross_wt"), Columns.decimalOrZero(rs, "net_wt"),
            Columns.decimalOrZero(rs, "fine_wt"), Columns.decimalOrZero(rs, "rate"), Columns.decimalOrZero(rs, "deduction_pct"),
            rs.getInt("quantity"), Columns.decimalOrZero(rs, "amount"), rs.getString("tag_code"));

    private static final String VIEW = """
            SELECT p.*, pa.name AS party_name, pa.phone AS party_phone,
                   (SELECT COUNT(*) FROM purchase_line l WHERE l.purchase_id = p.id) AS line_count
            FROM purchase p LEFT JOIN party pa ON pa.id = p.party_id""";
    private static final RowMapper<PurchaseView> VIEW_MAPPER = (rs, i) -> new PurchaseView(PURCHASE.mapRow(rs, i),
            rs.getString("party_name"), rs.getString("party_phone"), rs.getLong("line_count"));

    private final SqlSupport sql;

    public PurchaseRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public long insertHeader(String purchaseNo, LocalDate date, long partyId, PurchaseKind kind, String gstInvoiceNo,
                             PurchaseClass cls, Long rateSetId, String notes, String createdBy) {
        return sql.insert("""
                INSERT INTO purchase (purchase_no, business_date, party_id, purchase_kind, payment_mode, gst_invoice_no,
                                      purchase_class, rate_set_id, notes, created_by)
                VALUES (?,?,?,?, 'CREDIT', ?,?,?,?,?)""", purchaseNo, date, partyId, kind.name(), gstInvoiceNo, cls.name(), rateSetId,
                notes, createdBy);
    }

    public void updateSettlement(long id, SettlementMode mode, PurchaseTotals t, PaymentLegs legs) {
        sql.update("""
                UPDATE purchase SET payment_mode = ?, taxable_amount = ?, gst_amount = ?, total_amount = ?, cash_paid = ?,
                    bank_paid = ?, bank_ref = ?, gold_fine_paid = ?, silver_fine_paid = ?, metal_value_paid = ?, balance_due = ?
                WHERE id = ?""", mode.name(), t.taxable(), t.gst(), t.total(), legs.cash(), legs.bank(), legs.bankRef(),
                legs.goldFine(), legs.silverFine(), t.metalValuePaid(), t.balanceDue(), id);
    }

    public void insertLine(PurchaseLine l) {
        sql.update("""
                INSERT INTO purchase_line (purchase_id, item_id, description, metal, purity_code, gross_wt, net_wt, fine_wt, rate,
                                           deduction_pct, quantity, amount)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""", l.purchaseId(), l.itemId(), l.description(), Columns.name(l.metal()),
                l.purityCode(), l.grossWt(), l.netWt(), l.fineWt(), l.rate(), l.deductionPct(), l.quantity(), l.amount());
    }

    public Optional<PurchaseView> findView(long id) {
        return sql.one(VIEW + " WHERE p.id = ?", VIEW_MAPPER, id);
    }

    public List<PurchaseLine> findLines(long purchaseId) {
        return sql.list("""
                SELECT l.*, i.tag_code FROM purchase_line l LEFT JOIN item i ON i.id = l.item_id
                WHERE l.purchase_id = ? ORDER BY l.id""", LINE, purchaseId);
    }

    public List<PurchaseView> list(PurchaseClass cls, SettlementMode mode, LocalDate from, LocalDate to) {
        StringBuilder where = new StringBuilder(" WHERE p.business_date BETWEEN ? AND ?");
        List<Object> args = new ArrayList<>(List.of(from, to));
        if (cls != null) { where.append(" AND p.purchase_class = ?"); args.add(cls.name()); }
        if (mode != null) { where.append(" AND p.payment_mode = ?"); args.add(mode.name()); }
        return sql.list(VIEW + where + " ORDER BY p.id DESC", VIEW_MAPPER, args.toArray());
    }

    public List<Purchase> findByParty(long partyId) {
        return sql.list("SELECT * FROM purchase WHERE party_id = ? ORDER BY id DESC", PURCHASE, partyId);
    }

    public void updateClass(long id, PurchaseClass cls) {
        sql.update("UPDATE purchase SET purchase_class = ? WHERE id = ?", cls.name(), id);
    }

    public DayTotals totalsOn(LocalDate date) {
        return sql.one("SELECT COUNT(*) AS n, COALESCE(SUM(total_amount), 0) AS total FROM purchase WHERE business_date = ?",
                (rs, i) -> new DayTotals(rs.getLong("n"), Columns.decimalOrZero(rs, "total")), date).orElseThrow();
    }
}
