package com.swarnos.backup.repository;

import com.swarnos.backup.domain.BackupLogEntry;
import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class BackupLogRepository {
    private static final RowMapper<BackupLogEntry> MAPPER = (rs, i) -> new BackupLogEntry(rs.getLong("id"), Columns.instant(rs, "at"),
            rs.getString("username"), rs.getString("file_name"), rs.getString("target"), rs.getLong("size_bytes"),
            rs.getString("sha256"), rs.getLong("row_count"), rs.getBoolean("verified"));

    private final SqlSupport sql;

    public BackupLogRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public void insert(String username, String fileName, String target, long size, String sha256, long rows, boolean verified) {
        sql.update("INSERT INTO backup_log (username, file_name, target, size_bytes, sha256, row_count, verified) VALUES (?,?,?,?,?,?,?)",
                username, fileName, target, size, sha256, rows, verified);
    }

    public List<BackupLogEntry> findAll() {
        return sql.list("SELECT * FROM backup_log ORDER BY id DESC", MAPPER);
    }

    public Optional<BackupLogEntry> findByFileName(String fileName) {
        return sql.one("SELECT * FROM backup_log WHERE file_name = ? ORDER BY id DESC LIMIT 1", MAPPER, fileName);
    }

    public Optional<Instant> lastBackupAt() {
        return sql.one("SELECT at FROM backup_log ORDER BY id DESC LIMIT 1", (rs, i) -> Columns.instant(rs, "at"));
    }
}
