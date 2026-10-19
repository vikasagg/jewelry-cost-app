package com.swarnos.sales.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.sales.domain.BillQuote;
import com.swarnos.sales.domain.CustomerExchange;
import com.swarnos.sales.domain.CustomerPurchase;
import com.swarnos.sales.domain.ExchangeLine;
import com.swarnos.sales.domain.QuotedExchange;
import com.swarnos.sales.domain.QuotedLine;
import com.swarnos.sales.domain.Sale;
import com.swarnos.sales.domain.SaleLine;
import com.swarnos.sales.domain.SaleStatus;
import com.swarnos.sales.domain.SaleView;
import com.swarnos.sales.domain.SalesDayStats;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class SaleRepository {
    private static final RowMapper<Sale> SALE = (rs, i) -> new Sale(rs.getLong("id"), rs.getString("invoice_no"),
            Columns.date(rs, "business_date"), Columns.longOrNull(rs, "customer_id"), rs.getLong("rate_set_id"),
            Columns.decimalOrZero(rs, "items_total"), Columns.decimalOrZero(rs, "discount"), Columns.decimalOrZero(rs, "taxable_total"),
            Columns.decimalOrZero(rs, "gst_total"), Columns.decimalOrZero(rs, "exchange_total"), Columns.decimalOrZero(rs, "round_off"),
            Columns.decimalOrZero(rs, "net_payable"), Columns.decimalOrZero(rs, "paid_total"), Columns.decimalOrZero(rs, "balance_due"),
            SaleStatus.valueOf(rs.getString("status")), rs.getString("notes"), rs.getString("created_by"), Columns.instant(rs, "created_at"));
    private static final String VIEW = """
            SELECT s.*, p.name AS customer_name, p.phone AS customer_phone, p.address AS customer_address,
                   p.gstin AS customer_gstin, p.pan AS customer_pan,
                   (SELECT COUNT(*) FROM sale_line l WHERE l.sale_id = s.id) AS item_count
            FROM sale s LEFT JOIN party p ON p.id = s.customer_id""";
    private static final RowMapper<SaleView> VIEW_MAPPER = (rs, i) -> new SaleView(SALE.mapRow(rs, i), rs.getString("customer_name"),
            rs.getString("customer_phone"), rs.getString("customer_address"), rs.getString("customer_gstin"),
            rs.getString("customer_pan"), rs.getLong("item_count"));
    private static final RowMapper<SaleLine> LINE = (rs, i) -> new SaleLine(rs.getLong("id"), rs.getLong("sale_id"),
            rs.getLong("item_id"), rs.getString("description"), Columns.enumOrNull(rs, "metal", Metal.class), rs.getString("purity_code"),
            rs.getInt("quantity"), Columns.decimalOrZero(rs, "net_wt"), Columns.decimalOrZero(rs, "rate"),
            Columns.decimalOrZero(rs, "metal_value"), Columns.decimalOrZero(rs, "wastage_value"), Columns.decimalOrZero(rs, "making_value"),
            Columns.decimalOrZero(rs, "stone_value"), Columns.decimalOrZero(rs, "discount"), Columns.decimalOrZero(rs, "taxable"),
            Columns.decimalOrZero(rs, "gst_pct"), Columns.decimalOrZero(rs, "gst"), Columns.decimalOrZero(rs, "line_total"),
            rs.getString("huid"), rs.getString("tag_code"), Columns.decimalOrZero(rs, "item_gross_wt"),
            Columns.decimalOrZero(rs, "item_stone_wt"));
    private static final RowMapper<ExchangeLine> EXCHANGE = (rs, i) -> new ExchangeLine(rs.getLong("id"), rs.getLong("sale_id"),
            rs.getString("description"), Metal.valueOf(rs.getString("metal")), rs.getString("purity_code"),
            Columns.decimalOrZero(rs, "gross_wt"), Columns.decimalOrZero(rs, "net_wt"), Columns.decimalOrZero(rs, "fine_wt"),
            Columns.decimalOrZero(rs, "rate"), Columns.decimalOrZero(rs, "deduction_pct"), Columns.decimalOrZero(rs, "exchange_value"));

    private final SqlSupport sql;

    public SaleRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public long insert(String invoiceNo, LocalDate date, Long customerId, BillQuote q, BigDecimal paid, BigDecimal balance,
                       String notes, String createdBy) {
        return sql.insert("""
                INSERT INTO sale (invoice_no, business_date, customer_id, rate_set_id, items_total, discount, taxable_total,
                                  gst_total, exchange_total, round_off, net_payable, paid_total, balance_due, status, notes, created_by)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?, 'FINAL', ?, ?)""", invoiceNo, date, customerId, q.rateSetId(), q.itemsTotal(),
                q.discount(), q.taxableTotal(), q.gstTotal(), q.exchangeTotal(), q.roundOff(), q.netPayable(), paid, balance, notes,
                createdBy);
    }

    public void insertLine(long saleId, QuotedLine l) {
        sql.update("""
                INSERT INTO sale_line (sale_id, item_id, description, metal, purity_code, quantity, net_wt, rate, metal_value,
                    wastage_value, making_value, stone_value, discount, taxable, gst_pct, gst, line_total, huid)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""", saleId, l.itemId(), l.description(), Columns.name(l.metal()),
                l.purityCode(), l.quantity(), l.netWt(), l.rate(), l.metalValue(), l.wastageValue(), l.makingValue(), l.stoneValue(),
                l.discount(), l.taxable(), l.gstPct(), l.gst(), l.lineTotal(), l.huid());
    }

    public void insertExchange(long saleId, QuotedExchange x) {
        sql.update("""
                INSERT INTO sale_exchange (sale_id, description, metal, purity_code, gross_wt, net_wt, fine_wt, rate,
                                           deduction_pct, exchange_value) VALUES (?,?,?,?,?,?,?,?,?,?)""",
                saleId, x.description(), x.metal().name(), x.purityCode(), x.grossWt(), x.netWt(), x.fineWt(), x.rate(),
                x.deductionPct(), x.value());
    }

    public Optional<SaleView> findView(long id) {
        return sql.one(VIEW + " WHERE s.id = ?", VIEW_MAPPER, id);
    }

    public List<SaleLine> findLines(long saleId) {
        return sql.list("""
                SELECT l.*, i.tag_code, i.gross_wt AS item_gross_wt, i.stone_wt AS item_stone_wt
                FROM sale_line l JOIN item i ON i.id = l.item_id WHERE l.sale_id = ? ORDER BY l.id""", LINE, saleId);
    }

    public List<ExchangeLine> findExchange(long saleId) {
        return sql.list("SELECT * FROM sale_exchange WHERE sale_id = ? ORDER BY id", EXCHANGE, saleId);
    }

    public List<SaleView> list(LocalDate from, LocalDate to, String text) {
        String like = "%" + (text == null ? "" : text.trim().toLowerCase()) + "%";
        return sql.list(VIEW + """
                 WHERE s.business_date BETWEEN ? AND ? AND (LOWER(s.invoice_no) LIKE ? OR LOWER(COALESCE(p.name, '')) LIKE ?
                      OR COALESCE(p.phone, '') LIKE ?)
                ORDER BY s.id DESC""", VIEW_MAPPER, from, to, like, like, like);
    }

    public List<SaleView> recent(int limit) {
        return sql.list(VIEW + " ORDER BY s.id DESC LIMIT " + limit, VIEW_MAPPER);
    }

    public List<Sale> findByCustomer(long customerId) {
        return sql.list("SELECT * FROM sale WHERE customer_id = ? ORDER BY id DESC", SALE, customerId);
    }

    public void markReturned(long id, String notes) {
        sql.update("UPDATE sale SET status = 'RETURNED', notes = ? WHERE id = ?", notes, id);
    }

    public SalesDayStats statsOn(LocalDate date) {
        return sql.one("""
                SELECT COUNT(*) AS bills, COALESCE(SUM(net_payable), 0) AS net, COALESCE(SUM(gst_total), 0) AS gst,
                       (SELECT COUNT(*) FROM sale_line l JOIN sale s2 ON s2.id = l.sale_id
                        WHERE s2.business_date = ? AND s2.status = 'FINAL') AS pieces
                FROM sale WHERE business_date = ? AND status = 'FINAL'""",
                (rs, i) -> new SalesDayStats(rs.getLong("bills"), Columns.decimalOrZero(rs, "net"), Columns.decimalOrZero(rs, "gst"),
                        rs.getLong("pieces")), date, date).orElseThrow();
    }

    public List<CustomerPurchase> itemsBoughtBy(long customerId) {
        return sql.list("""
                SELECT s.invoice_no, s.business_date, s.status, l.description, l.purity_code, l.net_wt, l.rate, l.line_total, i.tag_code
                FROM sale_line l JOIN sale s ON s.id = l.sale_id JOIN item i ON i.id = l.item_id
                WHERE s.customer_id = ? ORDER BY s.id DESC, l.id""",
                (rs, i) -> new CustomerPurchase(rs.getString("invoice_no"), Columns.date(rs, "business_date"),
                        SaleStatus.valueOf(rs.getString("status")), rs.getString("description"), rs.getString("purity_code"),
                        Columns.decimalOrZero(rs, "net_wt"), Columns.decimalOrZero(rs, "rate"), Columns.decimalOrZero(rs, "line_total"),
                        rs.getString("tag_code")), customerId);
    }

    public List<CustomerExchange> exchangesBy(long customerId) {
        return sql.list("""
                SELECT s.invoice_no, s.business_date, x.description, x.metal, x.purity_code, x.net_wt, x.exchange_value
                FROM sale_exchange x JOIN sale s ON s.id = x.sale_id WHERE s.customer_id = ? ORDER BY s.id DESC""",
                (rs, i) -> new CustomerExchange(rs.getString("invoice_no"), Columns.date(rs, "business_date"),
                        rs.getString("description"), rs.getString("metal"), rs.getString("purity_code"),
                        Columns.decimalOrZero(rs, "net_wt"), Columns.decimalOrZero(rs, "exchange_value")), customerId);
    }
}
