package com.aijewel.erp.common;

import com.aijewel.erp.auth.CurrentUser;
import org.springframework.stereotype.Service;

/** Immutable audit trail of every important action (BRD §18 Auditability). */
@Service
public class AuditService {
    private final Db db;

    public AuditService(Db db) {
        this.db = db;
    }

    public void log(String action, String entity, Object entityId, String detail) {
        db.update("INSERT INTO audit_log (username, action, entity, entity_id, detail) VALUES (?,?,?,?,?)",
                CurrentUser.usernameOrSystem(), action, entity, entityId == null ? null : entityId.toString(),
                detail == null ? null : detail.length() > 1000 ? detail.substring(0, 1000) : detail);
    }
}
