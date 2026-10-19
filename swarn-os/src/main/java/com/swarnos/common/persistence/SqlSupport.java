package com.swarnos.common.persistence;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Component;

/**
 * Thin wrapper over the current shop's database for repositories. The
 * underlying data source routes every call to the signed-in shop's database.
 */
@Component
public class SqlSupport {
    private final JdbcClient jdbc;

    public SqlSupport(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public <T> List<T> list(String sql, RowMapper<T> mapper, Object... args) {
        return jdbc.sql(sql).params(args).query(mapper).list();
    }

    public <T> Optional<T> one(String sql, RowMapper<T> mapper, Object... args) {
        return jdbc.sql(sql).params(args).query(mapper).optional();
    }

    public <T> T scalar(String sql, Class<T> type, Object... args) {
        return jdbc.sql(sql).params(args).query(type).optional().orElse(null);
    }

    /** Untyped rows: only for tabular read models such as reports and backups. */
    public List<Map<String, Object>> rows(String sql, Object... args) {
        return jdbc.sql(sql).params(args).query().listOfRows();
    }

    public int update(String sql, Object... args) {
        return jdbc.sql(sql).params(args).update();
    }

    public long insert(String sql, Object... args) {
        KeyHolder keys = new GeneratedKeyHolder();
        jdbc.sql(sql).params(args).update(keys, "id");
        return keys.getKey().longValue();
    }
}
