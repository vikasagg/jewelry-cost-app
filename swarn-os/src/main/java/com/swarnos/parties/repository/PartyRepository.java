package com.swarnos.parties.repository;

import com.swarnos.common.persistence.Columns;
import com.swarnos.common.persistence.SqlSupport;
import com.swarnos.parties.domain.Party;
import com.swarnos.parties.domain.PartyDetails;
import com.swarnos.parties.domain.PartyType;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class PartyRepository {
    private static final RowMapper<Party> MAPPER = (rs, i) -> new Party(rs.getLong("id"), PartyType.valueOf(rs.getString("party_type")),
            rs.getString("name"), rs.getString("phone"), rs.getString("email"), rs.getString("address"), rs.getString("gstin"),
            rs.getString("pan"), rs.getString("id_proof"), Columns.date(rs, "birthday"), Columns.date(rs, "anniversary"),
            rs.getString("notes"), Columns.instant(rs, "created_at"));

    private final SqlSupport sql;

    public PartyRepository(SqlSupport sql) {
        this.sql = sql;
    }

    public List<Party> search(PartyType type, String text, int limit) {
        String like = "%" + (text == null ? "" : text.trim().toLowerCase()) + "%";
        String typeName = type == null ? "" : type.name();
        return sql.list("""
                SELECT * FROM party WHERE (? = '' OR party_type = ?) AND (LOWER(name) LIKE ? OR COALESCE(phone, '') LIKE ?)
                ORDER BY name""" + " LIMIT " + limit, MAPPER, typeName, typeName, like, like);
    }

    public Optional<Party> findById(long id) {
        return sql.one("SELECT * FROM party WHERE id = ?", MAPPER, id);
    }

    public long insert(PartyDetails d) {
        return sql.insert("""
                INSERT INTO party (party_type, name, phone, email, address, gstin, pan, id_proof, birthday, anniversary, notes)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)""", d.partyType().name(), d.name(), d.phone(), d.email(), d.address(), d.gstin(),
                d.pan(), d.idProof(), d.birthday(), d.anniversary(), d.notes());
    }

    public void update(long id, PartyDetails d) {
        sql.update("""
                UPDATE party SET party_type = ?, name = ?, phone = ?, email = ?, address = ?, gstin = ?, pan = ?, id_proof = ?,
                    birthday = ?, anniversary = ?, notes = ? WHERE id = ?""", d.partyType().name(), d.name(), d.phone(), d.email(),
                d.address(), d.gstin(), d.pan(), d.idProof(), d.birthday(), d.anniversary(), d.notes(), id);
    }
}
