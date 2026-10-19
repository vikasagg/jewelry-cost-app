package com.swarnos.settings.repository;

import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.Purity;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class PurityRepository {
    private static final RowMapper<Purity> MAPPER = (rs, i) -> new Purity(rs.getLong("id"), Metal.valueOf(rs.getString("metal")),
            rs.getString("code"), rs.getBigDecimal("price_factor"), rs.getBigDecimal("fineness"), rs.getInt("sort_order"),
            rs.getBoolean("active"));

    private final SqlSupport sql;

    public PurityRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public List<Purity> findActive() {
        return sql.list("SELECT * FROM purity WHERE active = TRUE ORDER BY metal, sort_order", MAPPER);
    }

    public Optional<Purity> findById(long id) {
        return sql.one("SELECT * FROM purity WHERE id = ?", MAPPER, id);
    }

    public Optional<Purity> find(Metal metal, String code) {
        return sql.one("SELECT * FROM purity WHERE metal = ? AND code = ?", MAPPER, metal.name(), code);
    }

    public void updatePriceFactor(long id, BigDecimal factor) {
        sql.update("UPDATE purity SET price_factor = ? WHERE id = ?", factor, id);
    }
}
