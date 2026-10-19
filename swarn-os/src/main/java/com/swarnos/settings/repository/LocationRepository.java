package com.swarnos.settings.repository;

import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.settings.domain.Location;
import com.swarnos.settings.domain.LocationKind;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class LocationRepository {
    private static final RowMapper<Location> MAPPER = (rs, i) -> new Location(rs.getLong("id"), rs.getString("code"),
            rs.getString("name"), LocationKind.valueOf(rs.getString("kind")));

    private final SqlSupport sql;

    public LocationRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public List<Location> findAll() {
        return sql.list("SELECT * FROM location ORDER BY id", MAPPER);
    }

    public Optional<Location> findById(long id) {
        return sql.one("SELECT * FROM location WHERE id = ?", MAPPER, id);
    }

    public Optional<Location> findByCode(String code) {
        return sql.one("SELECT * FROM location WHERE code = ?", MAPPER, code);
    }
}
