package com.swarnos.tenant.infrastructure;

import com.swarnos.tenant.domain.Tenant;
import com.zaxxer.hikari.HikariDataSource;
import jakarta.annotation.PreDestroy;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;
import javax.sql.DataSource;
import org.springframework.stereotype.Component;

/** One connection pool per shop database, opened on first use. */
@Component
public class TenantDataSources {
    private final DataPaths paths;
    private final Map<String, HikariDataSource> pools = new ConcurrentHashMap<>();
    private Function<String, Tenant> tenantLookup;

    public TenantDataSources(DataPaths paths) {
        this.paths = paths;
    }

    /** Set by the tenant service at start-up (avoids a dependency from infrastructure to services). */
    public void setTenantLookup(Function<String, Tenant> lookup) {
        this.tenantLookup = lookup;
    }

    public DataSource forTenant(String code) {
        return pools.computeIfAbsent(code, c -> {
            Tenant t = tenantLookup.apply(c);
            return ConnectionPools.create("tenant-" + c, resolveUrl(t.jdbcUrl()), t.dbUsername(), t.dbPassword(), 8);
        });
    }

    public void close(String code) {
        HikariDataSource ds = pools.remove(code);
        if (ds != null) ds.close();
    }

    public String resolveUrl(String stored) {
        return stored.startsWith(Tenant.LOCAL_URL_PREFIX)
                ? DataPaths.h2Url(paths.root().resolve(stored.substring(Tenant.LOCAL_URL_PREFIX.length())))
                : stored;
    }

    @PreDestroy
    void closeAll() {
        pools.values().forEach(HikariDataSource::close);
    }
}
