package com.swarnos.inventory.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.inventory.domain.Item;
import com.swarnos.inventory.domain.ItemCriteria;
import com.swarnos.inventory.domain.ItemListing;
import com.swarnos.inventory.domain.ItemStatus;
import com.swarnos.inventory.domain.PurchaseClass;
import com.swarnos.inventory.domain.StatusMismatch;
import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.PricingMode;
import com.swarnos.settings.domain.ProductFamily;
import com.swarnos.settings.domain.Tracking;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class ItemRepository {
    /** Item with its category rules, location and vendor names, and stone totals. */
    private static final String LISTING = """
            SELECT i.*, c.code AS category_code, c.name AS category_name, c.family, c.pricing_mode, c.tracking, c.gst_pct,
                   c.making_type AS cat_making_type, c.making_value AS cat_making_value, c.wastage_pct AS cat_wastage_pct,
                   l.name AS location_name, v.name AS vendor_name,
                   (SELECT COALESCE(SUM(s.stone_value), 0) FROM stone s WHERE s.item_id = i.id) AS stone_total,
                   (SELECT COALESCE(SUM(s.carat), 0) FROM stone s WHERE s.item_id = i.id) AS stone_carat,
                   (SELECT MIN(s.stone_type) FROM stone s WHERE s.item_id = i.id) AS stone_type
            FROM item i
            JOIN category c ON c.id = i.category_id
            LEFT JOIN location l ON l.id = i.location_id
            LEFT JOIN party v ON v.id = i.vendor_id
            """;

    static final RowMapper<Item> ITEM = (rs, i) -> new Item(rs.getLong("id"), rs.getString("tag_code"), rs.getString("rfid_epc"),
            rs.getLong("category_id"), rs.getString("name"), Columns.enumOrNull(rs, "metal", Metal.class), rs.getString("purity_code"),
            Columns.decimalOrZero(rs, "gross_wt"), Columns.decimalOrZero(rs, "stone_wt"), Columns.decimalOrZero(rs, "net_wt"),
            Columns.enumOrNull(rs, "making_type", MakingType.class), Columns.decimal(rs, "making_value"),
            Columns.decimal(rs, "wastage_pct"), Columns.decimal(rs, "fixed_price"), rs.getInt("quantity"), rs.getString("huid"),
            rs.getString("design_code"), rs.getString("collection"), Columns.longOrNull(rs, "location_id"),
            ItemStatus.valueOf(rs.getString("status")), Columns.longOrNull(rs, "vendor_id"), Columns.longOrNull(rs, "purchase_id"),
            Columns.enumOrNull(rs, "purchase_class", PurchaseClass.class), Columns.decimal(rs, "cost_amount"), rs.getString("notes"),
            rs.getString("created_by"), Columns.instant(rs, "created_at"));

    private static final RowMapper<ItemListing> LISTING_MAPPER = (rs, i) -> new ItemListing(ITEM.mapRow(rs, i),
            rs.getString("category_code"), rs.getString("category_name"), ProductFamily.valueOf(rs.getString("family")),
            PricingMode.valueOf(rs.getString("pricing_mode")), Tracking.valueOf(rs.getString("tracking")),
            Columns.decimalOrZero(rs, "gst_pct"), MakingType.valueOf(rs.getString("cat_making_type")),
            Columns.decimalOrZero(rs, "cat_making_value"), Columns.decimalOrZero(rs, "cat_wastage_pct"),
            rs.getString("location_name"), rs.getString("vendor_name"), Columns.decimalOrZero(rs, "stone_total"),
            Columns.decimalOrZero(rs, "stone_carat"), rs.getString("stone_type"));

    private final SqlSupport sql;

    public ItemRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public long insert(Item i) {
        return sql.insert("""
                INSERT INTO item (tag_code, category_id, name, metal, purity_code, gross_wt, stone_wt, net_wt, making_type,
                    making_value, wastage_pct, fixed_price, quantity, huid, design_code, collection, location_id, status,
                    vendor_id, purchase_id, purchase_class, cost_amount, notes, created_by)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                i.tagCode(), i.categoryId(), i.name(), Columns.name(i.metal()), i.purityCode(), i.grossWt(), i.stoneWt(), i.netWt(),
                Columns.name(i.makingType()), i.makingValue(), i.wastagePct(), i.fixedPrice(), i.quantity(), i.huid(),
                i.designCode(), i.collection(), i.locationId(), i.status().name(), i.vendorId(), i.purchaseId(),
                Columns.name(i.purchaseClass()), i.costAmount(), i.notes(), i.createdBy());
    }

    public Optional<Item> findById(long id) {
        return sql.one("SELECT * FROM item WHERE id = ?", ITEM, id);
    }

    public Optional<ItemListing> findListing(long id) {
        return sql.one(LISTING + " WHERE i.id = ?", LISTING_MAPPER, id);
    }

    public List<ItemListing> findListings(Collection<Long> ids) {
        if (ids.isEmpty()) return List.of();
        String in = String.join(",", Collections.nCopies(ids.size(), "?"));
        return sql.list(LISTING + " WHERE i.id IN (" + in + ") ORDER BY i.id", LISTING_MAPPER, ids.toArray());
    }

    /** Matches the printed QR tag code, or an RFID EPC once tags are encoded. */
    public Optional<Long> findIdByCode(String code) {
        return sql.one("SELECT id FROM item WHERE UPPER(tag_code) = UPPER(?) OR UPPER(rfid_epc) = UPPER(?)",
                (rs, i) -> rs.getLong("id"), code, code);
    }

    /** Latest item whose tag ends with the spoken digits ("tag 45" -> T000045). */
    public Optional<Long> findIdByCodeSuffix(String digits) {
        return sql.one("SELECT id FROM item WHERE tag_code LIKE ? ORDER BY id DESC LIMIT 1", (rs, i) -> rs.getLong("id"), "%" + digits);
    }

    public List<ItemListing> search(ItemCriteria c) {
        StringBuilder where = new StringBuilder(" WHERE 1=1");
        List<Object> args = new ArrayList<>();
        if (c.status() != null) { where.append(" AND i.status = ?"); args.add(c.status().name()); }
        if (c.categoryId() != null) { where.append(" AND i.category_id = ?"); args.add(c.categoryId()); }
        if (c.family() != null) { where.append(" AND c.family = ?"); args.add(c.family().name()); }
        if (c.metal() != null) { where.append(" AND i.metal = ?"); args.add(c.metal().name()); }
        if (c.purity() != null) { where.append(" AND i.purity_code = ?"); args.add(c.purity()); }
        if (c.locationId() != null) { where.append(" AND i.location_id = ?"); args.add(c.locationId()); }
        if (c.minWt() != null) { where.append(" AND i.net_wt >= ?"); args.add(c.minWt()); }
        if (c.maxWt() != null) { where.append(" AND i.net_wt <= ?"); args.add(c.maxWt()); }
        if (c.purchaseClass() != null) { where.append(" AND i.purchase_class = ?"); args.add(c.purchaseClass().name()); }
        if (c.stoneType() != null) {
            where.append(" AND EXISTS (SELECT 1 FROM stone s WHERE s.item_id = i.id AND s.stone_type = ?)");
            args.add(c.stoneType());
        }
        if (c.text() != null && !c.text().isBlank()) {
            String like = "%" + c.text().trim().toLowerCase() + "%";
            where.append(" AND (LOWER(i.tag_code) LIKE ? OR LOWER(i.name) LIKE ? OR LOWER(COALESCE(i.design_code,'')) LIKE ?"
                    + " OR LOWER(COALESCE(i.huid,'')) LIKE ? OR LOWER(c.name) LIKE ?)");
            for (int k = 0; k < 5; k++) args.add(like);
        }
        return sql.list(LISTING + where + " ORDER BY i.id DESC", LISTING_MAPPER, args.toArray());
    }

    public List<Long> findInStockIds(Long locationId, Long categoryId) {
        return sql.list("""
                SELECT id FROM item WHERE status = 'IN_STOCK'
                  AND (CAST(? AS BIGINT) IS NULL OR location_id = ?) AND (CAST(? AS BIGINT) IS NULL OR category_id = ?)
                ORDER BY id""", (rs, i) -> rs.getLong("id"), locationId, locationId, categoryId, categoryId);
    }

    public void updateDetails(Item i) {
        sql.update("""
                UPDATE item SET name = ?, gross_wt = ?, stone_wt = ?, net_wt = ?, making_type = ?, making_value = ?,
                    wastage_pct = ?, fixed_price = ?, huid = ?, design_code = ?, collection = ?, notes = ?
                WHERE id = ?""", i.name(), i.grossWt(), i.stoneWt(), i.netWt(), Columns.name(i.makingType()), i.makingValue(),
                i.wastagePct(), i.fixedPrice(), i.huid(), i.designCode(), i.collection(), i.notes(), i.id());
    }

    public void updateStatus(long id, ItemStatus status, Long locationId) {
        if (locationId == null) {
            sql.update("UPDATE item SET status = ? WHERE id = ?", status.name(), id);
        } else {
            sql.update("UPDATE item SET status = ?, location_id = ? WHERE id = ?", status.name(), locationId, id);
        }
    }

    public void updatePurchaseClass(long purchaseId, PurchaseClass cls) {
        sql.update("UPDATE item SET purchase_class = ? WHERE purchase_id = ?", cls.name(), purchaseId);
    }

    public List<StatusMismatch> findStatusMismatches() {
        return sql.list("""
                SELECT i.id, i.tag_code, i.status, m.status_after FROM item i
                LEFT JOIN stock_movement m ON m.id = (SELECT MAX(id) FROM stock_movement WHERE item_id = i.id)
                WHERE m.status_after IS NULL OR m.status_after <> i.status""",
                (rs, n) -> new StatusMismatch(rs.getLong("id"), rs.getString("tag_code"), ItemStatus.valueOf(rs.getString("status")),
                        Columns.enumOrNull(rs, "status_after", ItemStatus.class)));
    }
}
