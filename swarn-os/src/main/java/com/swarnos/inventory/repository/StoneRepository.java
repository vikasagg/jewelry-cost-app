package com.swarnos.inventory.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.inventory.domain.Stone;
import java.util.List;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class StoneRepository {
    private static final RowMapper<Stone> MAPPER = (rs, i) -> new Stone(rs.getLong("id"), rs.getLong("item_id"),
            rs.getString("stone_type"), rs.getInt("pieces"), Columns.decimalOrZero(rs, "carat"),
            Columns.decimalOrZero(rs, "rate_per_carat"), Columns.decimalOrZero(rs, "stone_value"), rs.getString("clarity"),
            rs.getString("colour"), rs.getString("certificate"));

    private final SqlSupport sql;

    public StoneRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public void insert(Stone s) {
        sql.update("""
                INSERT INTO stone (item_id, stone_type, pieces, carat, rate_per_carat, stone_value, clarity, colour, certificate)
                VALUES (?,?,?,?,?,?,?,?,?)""", s.itemId(), s.stoneType(), s.pieces(), s.carat(), s.ratePerCarat(), s.stoneValue(),
                s.clarity(), s.colour(), s.certificate());
    }

    public List<Stone> findByItem(long itemId) {
        return sql.list("SELECT * FROM stone WHERE item_id = ? ORDER BY id", MAPPER, itemId);
    }
}
