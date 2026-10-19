package com.swarnos.reports.repository;

import com.swarnos.common.persistence.SqlSupport;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Repository;

/**
 * Read-only reporting queries. Reports are a read model across modules, so this
 * repository may join any tables; it never writes.
 */
@Repository
public class ReportRepository {
    private final SqlSupport sql;

    public ReportRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public List<Map<String, Object>> salesRegister(LocalDate from, LocalDate to) {
        return sql.rows("""
                SELECT s.invoice_no, s.business_date, p.name AS customer, s.items_total, s.discount, s.gst_total,
                       s.exchange_total, s.net_payable, s.paid_total, s.balance_due, s.status, s.created_by
                FROM sale s LEFT JOIN party p ON p.id = s.customer_id WHERE s.business_date BETWEEN ? AND ? ORDER BY s.id""", from, to);
    }

    public List<Map<String, Object>> salesItems(LocalDate from, LocalDate to) {
        return sql.rows("""
                SELECT s.invoice_no, s.business_date, i.tag_code, l.description, l.net_wt, l.rate, l.making_value,
                       l.stone_value, l.discount, l.gst, l.line_total, s.status
                FROM sale_line l JOIN sale s ON s.id = l.sale_id JOIN item i ON i.id = l.item_id
                WHERE s.business_date BETWEEN ? AND ? ORDER BY s.id, l.id""", from, to);
    }

    public List<Map<String, Object>> salesByCategory(LocalDate from, LocalDate to) {
        return sql.rows("""
                SELECT c.name AS category, COUNT(*) AS pieces, SUM(l.net_wt) AS net_wt, SUM(l.taxable) AS taxable,
                       SUM(l.gst) AS gst, SUM(l.line_total) AS total
                FROM sale_line l JOIN sale s ON s.id = l.sale_id JOIN item i ON i.id = l.item_id
                JOIN category c ON c.id = i.category_id
                WHERE s.status = 'FINAL' AND s.business_date BETWEEN ? AND ? GROUP BY c.name ORDER BY total DESC""", from, to);
    }

    public List<Map<String, Object>> salesBySalesperson(LocalDate from, LocalDate to) {
        return sql.rows("""
                SELECT s.created_by AS salesperson, COUNT(*) AS bills, SUM(s.net_payable) AS net, SUM(s.discount) AS discount
                FROM sale s WHERE s.status = 'FINAL' AND s.business_date BETWEEN ? AND ?
                GROUP BY s.created_by ORDER BY net DESC""", from, to);
    }

    public List<Map<String, Object>> purchaseRegister(LocalDate from, LocalDate to) {
        return sql.rows("""
                SELECT p.purchase_no, p.business_date, pa.name AS party, p.purchase_kind, p.payment_mode, p.purchase_class,
                       p.gst_invoice_no, p.taxable_amount, p.gst_amount, p.total_amount, p.cash_paid, p.bank_paid,
                       p.gold_fine_paid, p.silver_fine_paid, p.balance_due
                FROM purchase p LEFT JOIN party pa ON pa.id = p.party_id WHERE p.business_date BETWEEN ? AND ? ORDER BY p.id""",
                from, to);
    }

    public List<Map<String, Object>> purchaseByMode(LocalDate from, LocalDate to) {
        return sql.rows("""
                SELECT payment_mode, COUNT(*) AS purchases, SUM(total_amount) AS total, SUM(cash_paid) AS cash,
                       SUM(bank_paid) AS bank, SUM(gold_fine_paid) AS gold_fine, SUM(silver_fine_paid) AS silver_fine,
                       SUM(balance_due) AS due
                FROM purchase WHERE business_date BETWEEN ? AND ? GROUP BY payment_mode ORDER BY payment_mode""", from, to);
    }

    public List<Map<String, Object>> purchaseByClass(LocalDate from, LocalDate to) {
        return sql.rows("""
                SELECT purchase_class, COUNT(*) AS purchases, SUM(taxable_amount) AS taxable, SUM(gst_amount) AS gst,
                       SUM(total_amount) AS total, SUM(cash_paid) AS cash_out, SUM(bank_paid) AS bank_out,
                       (SELECT COUNT(*) FROM item i WHERE i.purchase_class = p.purchase_class AND i.status = 'IN_STOCK') AS pieces_in_stock
                FROM purchase p WHERE business_date BETWEEN ? AND ? GROUP BY purchase_class ORDER BY purchase_class""", from, to);
    }

    public List<Map<String, Object>> oldMetal(LocalDate from, LocalDate to) {
        return sql.rows("""
                SELECT 'PURCHASE' AS source, p.purchase_no AS doc_no, p.business_date, l.metal, l.purity_code, l.gross_wt,
                       l.net_wt, l.fine_wt, l.deduction_pct, l.amount AS amount
                FROM purchase_line l JOIN purchase p ON p.id = l.purchase_id
                WHERE p.purchase_kind = 'OLD_METAL' AND p.business_date BETWEEN ? AND ?
                UNION ALL
                SELECT 'EXCHANGE', s.invoice_no, s.business_date, x.metal, x.purity_code, x.gross_wt, x.net_wt, x.fine_wt,
                       x.deduction_pct, x.exchange_value
                FROM sale_exchange x JOIN sale s ON s.id = x.sale_id WHERE s.business_date BETWEEN ? AND ?
                ORDER BY business_date""", from, to, from, to);
    }

    public List<Map<String, Object>> outstanding() {
        return sql.rows("""
                SELECT p.name, p.party_type, p.phone, SUM(e.debit - e.credit) AS balance
                FROM ledger_entry e JOIN party p ON p.id = e.party_id WHERE e.book = 'PARTY'
                GROUP BY p.id, p.name, p.party_type, p.phone HAVING SUM(e.debit - e.credit) <> 0 ORDER BY balance DESC""");
    }

    public List<Map<String, Object>> openRepairs(LocalDate today) {
        return sql.rows("""
                SELECT r.job_no, c.name AS customer, c.phone, r.description, r.weight_in, r.status, r.promised_date,
                       k.name AS karigar, CASE WHEN r.promised_date < ? THEN 'OVERDUE' ELSE '' END AS flag
                FROM repair_job r JOIN party c ON c.id = r.customer_id LEFT JOIN party k ON k.id = r.karigar_id
                WHERE r.status <> 'DELIVERED' ORDER BY r.promised_date""", today);
    }

    public List<Map<String, Object>> karigarDifference() {
        return sql.rows("""
                SELECT k.name AS karigar, COUNT(*) AS jobs, SUM(r.weight_issued) AS issued, SUM(r.weight_returned) AS returned,
                       SUM(r.weight_returned - r.weight_issued) AS difference
                FROM repair_job r JOIN party k ON k.id = r.karigar_id WHERE r.weight_returned IS NOT NULL
                GROUP BY k.name ORDER BY k.name""");
    }

    public List<Map<String, Object>> tallyHistory(LocalDate from, LocalDate to) {
        return sql.rows("""
                SELECT t.id, t.business_date, l.name AS location, c.name AS category, t.status, t.expected_count,
                       (SELECT COUNT(*) FROM tally_scan s WHERE s.session_id = t.id AND s.item_id IS NOT NULL) AS scanned,
                       (SELECT COUNT(*) FROM tally_variance v WHERE v.session_id = t.id AND v.kind = 'MISSING') AS missing,
                       (SELECT COUNT(*) FROM tally_variance v WHERE v.session_id = t.id AND v.resolution = 'MARK_LOST') AS marked_lost,
                       t.opened_by, t.closed_by
                FROM tally_session t LEFT JOIN location l ON l.id = t.location_id LEFT JOIN category c ON c.id = t.category_id
                WHERE t.business_date BETWEEN ? AND ? ORDER BY t.id DESC""", from, to);
    }

    public List<Map<String, Object>> rateHistory(LocalDate from, LocalDate to) {
        return sql.rows("""
                SELECT business_date, source, provider, gold_24k, silver_base, platinum_base, status, entered_by, approved_by
                FROM rate_set WHERE business_date BETWEEN ? AND ? ORDER BY id DESC""", from, to);
    }

    public List<Map<String, Object>> gstSummary(LocalDate from, LocalDate to) {
        return sql.rows("""
                SELECT l.gst_pct, COUNT(*) AS lines, SUM(l.taxable) AS taxable, SUM(l.gst) AS gst,
                       SUM(l.gst) / 2 AS cgst, SUM(l.gst) / 2 AS sgst
                FROM sale_line l JOIN sale s ON s.id = l.sale_id
                WHERE s.status = 'FINAL' AND s.business_date BETWEEN ? AND ? GROUP BY l.gst_pct ORDER BY l.gst_pct""", from, to);
    }

    public List<Map<String, Object>> huidRegister() {
        return sql.rows("""
                SELECT i.tag_code, i.huid, i.name, i.purity_code, i.net_wt, i.status,
                       (SELECT s.invoice_no FROM sale_line l JOIN sale s ON s.id = l.sale_id WHERE l.item_id = i.id
                        ORDER BY s.id DESC LIMIT 1) AS invoice_no
                FROM item i WHERE i.huid IS NOT NULL ORDER BY i.tag_code""");
    }

    public List<Map<String, Object>> backupLog() {
        return sql.rows("SELECT * FROM backup_log ORDER BY id DESC");
    }
}
