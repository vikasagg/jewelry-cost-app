package com.swarnos.common.audit.repository;

import com.swarnos.common.audit.domain.AuditEntry;
import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import java.util.List;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class AuditRepository {
    private static final RowMapper<AuditEntry> MAPPER = (rs, i) -> new AuditEntry(rs.getLong("id"), Columns.instant(rs, "at"),
            rs.getString("username"), rs.getString("action"), rs.getString("entity"), rs.getString("entity_id"), rs.getString("detail"));

    private final SqlSupport sql;

    public AuditRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public void insert(String username, String action, String entity, String entityId, String detail) {
        sql.update("INSERT INTO audit_log (username, action, entity, entity_id, detail) VALUES (?,?,?,?,?)",
                username, action, entity, entityId, detail);
    }

    public List<AuditEntry> latest(int limit) {
        return sql.list("SELECT * FROM audit_log ORDER BY id DESC LIMIT " + limit, MAPPER);
    }
}
