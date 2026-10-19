package com.aijewel.erp.common;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Component;

/**
 * Small helper over the current tenant's database. The underlying data source
 * routes every call to the signed-in shop's own database.
 */
@Component
public class Db {
    private final JdbcClient jdbc;

    public Db(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public List<Map<String, Object>> rows(String sql, Object... args) {
        return jdbc.sql(sql).params(args).query().listOfRows();
    }

    public Optional<Map<String, Object>> opt(String sql, Object... args) {
        List<Map<String, Object>> list = rows(sql, args);
        return list.isEmpty() ? Optional.empty() : Optional.of(list.get(0));
    }

    public Map<String, Object> one(String sql, String notFound, Object... args) {
        return opt(sql, args).orElseThrow(() -> ApiException.notFound(notFound));
    }

    public <T> T value(String sql, Class<T> type, Object... args) {
        return jdbc.sql(sql).params(args).query(type).optional().orElse(null);
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
