package com.swarnos.tenant.service;

import com.swarnos.common.error.BusinessException;
import com.swarnos.tenant.domain.Tenant;
import com.swarnos.tenant.domain.TenantStatus;
import com.swarnos.tenant.infrastructure.TenantDataSources;
import com.swarnos.tenant.repository.TenantRepository;
import java.util.List;
import java.util.Optional;
import org.springframework.stereotype.Service;

/** Read access to the shop registry, and suspending / resuming shops. */
@Service
public class TenantService {
    private final TenantRepository repository;

    public TenantService(TenantRepository repository, TenantDataSources dataSources) {
        this.repository = repository;
        dataSources.setTenantLookup(this::require);
    }

    public List<Tenant> list() {
        return repository.findAll();
    }

    public Optional<Tenant> find(String code) {
        return code == null ? Optional.empty() : repository.findByCode(code.trim().toLowerCase());
    }

    public Tenant require(String code) {
        return find(code).orElseThrow(() -> BusinessException.notFound("Unknown shop code: " + code));
    }

    public boolean isActive(String code) {
        return find(code).map(Tenant::isActive).orElse(false);
    }

    public Tenant setStatus(String code, TenantStatus status) {
        require(code);
        repository.updateStatus(code, status);
        return require(code);
    }
}
