package com.swarnos.identity.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.identity.domain.User;
import com.swarnos.security.Role;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class UserRepository {
    private static final RowMapper<User> MAPPER = (rs, i) -> new User(rs.getLong("id"), rs.getString("username"),
            rs.getString("full_name"), rs.getString("password_hash"), Role.valueOf(rs.getString("role")),
            rs.getBoolean("active"), Columns.instant(rs, "created_at"));

    private final SqlSupport sql;

    public UserRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public List<User> findAll() {
        return sql.list("SELECT * FROM app_user ORDER BY username", MAPPER);
    }

    public Optional<User> findById(long id) {
        return sql.one("SELECT * FROM app_user WHERE id = ?", MAPPER, id);
    }

    public Optional<User> findActiveByUsername(String username) {
        return sql.one("SELECT * FROM app_user WHERE username = ? AND active = TRUE", MAPPER, username);
    }

    public long insert(String username, String fullName, String passwordHash, Role role) {
        return sql.insert("INSERT INTO app_user (username, full_name, password_hash, role) VALUES (?,?,?,?)",
                username, fullName, passwordHash, role.name());
    }

    public void updateProfile(long id, String fullName, Role role, boolean active) {
        sql.update("UPDATE app_user SET full_name = ?, role = ?, active = ? WHERE id = ?", fullName, role.name(), active, id);
    }

    public void updatePassword(long id, String passwordHash) {
        sql.update("UPDATE app_user SET password_hash = ? WHERE id = ?", passwordHash, id);
    }
}
