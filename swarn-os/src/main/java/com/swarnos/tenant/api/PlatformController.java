package com.swarnos.tenant.api;

import com.swarnos.tenant.api.dto.CreateTenantRequest;
import com.swarnos.tenant.api.dto.TenantResponse;
import com.swarnos.tenant.domain.TenantStatus;
import com.swarnos.tenant.service.TenantProvisioningService;
import com.swarnos.tenant.service.TenantService;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Platform operator: onboard shops, upgrade databases, suspend or resume a shop. */
@RestController
@RequestMapping("/api/platform/tenants")
public class PlatformController {
    private final TenantService tenants;
    private final TenantProvisioningService provisioning;

    public PlatformController(TenantService tenants, TenantProvisioningService provisioning) {
        this.tenants = tenants;
        this.provisioning = provisioning;
    }

    @GetMapping
    public List<TenantResponse> list() {
        return tenants.list().stream().map(TenantResponse::from).toList();
    }

    @PostMapping
    public TenantResponse create(@RequestBody CreateTenantRequest req) {
        return TenantResponse.from(provisioning.create(new TenantProvisioningService.NewShop(req.code(), req.name(),
                req.storageMode(), req.ownerUsername(), req.ownerName(), req.ownerPassword())));
    }

    @PostMapping("/migrate")
    public Map<String, List<String>> migrateAll() {
        return Map.of("failed", provisioning.migrateAll());
    }

    @PostMapping("/{code}/status/{status}")
    public TenantResponse setStatus(@PathVariable String code, @PathVariable TenantStatus status) {
        return TenantResponse.from(tenants.setStatus(code, status));
    }
}
