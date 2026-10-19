package com.swarnos.common.audit.service;

import com.swarnos.common.audit.domain.AuditEntry;
import com.swarnos.common.audit.repository.AuditRepository;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import java.util.List;
import org.springframework.stereotype.Service;

/** Immutable audit trail of every important action (BRD §18 Auditability). */
@Service
public class AuditService {
    private static final int MAX_DETAIL = 1000;
    private final AuditRepository repository;

    public AuditService(AuditRepository repository) {
        this.repository = repository;
    }

    public void record(String action, String entity, Object entityId, String detail) {
        String d = detail == null || detail.length() <= MAX_DETAIL ? detail : detail.substring(0, MAX_DETAIL);
        repository.insert(CurrentUser.usernameOrSystem(), action, entity, entityId == null ? null : entityId.toString(), d);
    }

    public List<AuditEntry> latest() {
        CurrentUser.require(Permission.CONFIG);
        return repository.latest(300);
    }
}
