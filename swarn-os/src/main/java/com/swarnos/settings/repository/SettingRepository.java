package com.swarnos.settings.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.settings.domain.Setting;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class SettingRepository {
    private static final RowMapper<Setting> MAPPER = (rs, i) -> new Setting(rs.getString("config_key"),
            rs.getString("config_value"), rs.getString("description"), rs.getString("updated_by"), Columns.instant(rs, "updated_at"));

    private final SqlSupport sql;

    public SettingRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public List<Setting> findAll() {
        return sql.list("SELECT * FROM app_config ORDER BY config_key", MAPPER);
    }

    public Optional<Setting> find(String key) {
        return sql.one("SELECT * FROM app_config WHERE config_key = ?", MAPPER, key);
    }

    public boolean update(String key, String value, String by, Instant at) {
        return sql.update("UPDATE app_config SET config_value = ?, updated_by = ?, updated_at = ? WHERE config_key = ?",
                value, by, Columns.timestamp(at), key) > 0;
    }
}
