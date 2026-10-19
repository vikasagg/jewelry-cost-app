package com.aijewel.erp.tenant;

import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Platform operator: onboard shops, run upgrades, suspend or resume a shop. */
@RestController
@RequestMapping("/api/platform")
public class PlatformController {
    private final TenantRegistry registry;
    private final TenantProvisioner provisioner;

    public PlatformController(TenantRegistry registry, TenantProvisioner provisioner) {
        this.registry = registry;
        this.provisioner = provisioner;
    }

    @GetMapping("/tenants")
    public List<Map<String, Object>> tenants() {
        return registry.list().stream().map(t -> Map.<String, Object>of(
                "code", t.code(), "name", t.name(), "storageMode", t.storageMode(),
                "database", t.storageMode().equals("LOCAL") ? "data/" + t.jdbcUrl().substring(3) : t.jdbcUrl(),
                "status", t.status(), "schemaVersion", t.schemaVersion() == null ? "" : t.schemaVersion())).toList();
    }

    @PostMapping("/tenants")
    public Map<String, Object> create(@RequestBody TenantProvisioner.NewTenant req) {
        TenantInfo t = provisioner.create(req);
        return Map.of("code", t.code(), "name", t.name(), "storageMode", t.storageMode());
    }

    @PostMapping("/tenants/migrate")
    public Map<String, Object> migrateAll() {
        return Map.of("failed", provisioner.migrateAll());
    }

    @PostMapping("/tenants/{code}/status/{status}")
    public Map<String, Object> status(@PathVariable String code, @PathVariable String status) {
        registry.require(code);
        String s = status.equalsIgnoreCase("ACTIVE") ? "ACTIVE" : "SUSPENDED";
        registry.setStatus(code, s);
        return Map.of("code", code, "status", s);
    }
}
