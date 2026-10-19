package com.swarnos.settings.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.settings.domain.Category;
import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.PricingMode;
import com.swarnos.settings.domain.ProductFamily;
import com.swarnos.settings.domain.Tracking;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class CategoryRepository {
    private static final RowMapper<Category> MAPPER = (rs, i) -> new Category(rs.getLong("id"), rs.getString("code"),
            rs.getString("name"), ProductFamily.valueOf(rs.getString("family")), Columns.enumOrNull(rs, "metal", Metal.class),
            PricingMode.valueOf(rs.getString("pricing_mode")), Tracking.valueOf(rs.getString("tracking")),
            rs.getString("tag_type"), MakingType.valueOf(rs.getString("making_type")), Columns.decimalOrZero(rs, "making_value"),
            Columns.decimalOrZero(rs, "wastage_pct"), Columns.decimalOrZero(rs, "gst_pct"), rs.getBoolean("active"));

    private final SqlSupport sql;

    public CategoryRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public List<Category> findActive() {
        return sql.list("SELECT * FROM category WHERE active = TRUE ORDER BY family, name", MAPPER);
    }

    public Optional<Category> findById(long id) {
        return sql.one("SELECT * FROM category WHERE id = ?", MAPPER, id);
    }

    public long insert(Category c) {
        return sql.insert("""
                INSERT INTO category (code, name, family, metal, pricing_mode, tracking, tag_type, making_type,
                                      making_value, wastage_pct, gst_pct) VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
                c.code(), c.name(), c.family().name(), Columns.name(c.metal()), c.pricingMode().name(), c.tracking().name(),
                c.tagType(), c.makingType().name(), c.makingValue(), c.wastagePct(), c.gstPct());
    }

    public void update(Category c) {
        sql.update("""
                UPDATE category SET name = ?, making_type = ?, making_value = ?, wastage_pct = ?, gst_pct = ?, active = ?
                WHERE id = ?""", c.name(), c.makingType().name(), c.makingValue(), c.wastagePct(), c.gstPct(), c.active(), c.id());
    }
}
