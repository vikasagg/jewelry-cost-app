package com.swarnos.settings.service;

import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.settings.domain.Category;
import com.swarnos.settings.domain.Location;
import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.Metal;
import com.swarnos.settings.domain.ProductFamily;
import com.swarnos.settings.domain.Purity;
import com.swarnos.settings.domain.Tracking;
import com.swarnos.settings.repository.CategoryRepository;
import com.swarnos.settings.repository.LocationRepository;
import com.swarnos.settings.repository.PurityRepository;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Categories, purities and stock locations. */
@Service
public class MasterDataService {
    private static final BigDecimal MAX_FACTOR = BigDecimal.valueOf(2);

    private final CategoryRepository categories;
    private final PurityRepository purities;
    private final LocationRepository locations;
    private final AuditService audit;

    public MasterDataService(CategoryRepository categories, PurityRepository purities, LocationRepository locations,
                             AuditService audit) {
        this.categories = categories;
        this.purities = purities;
        this.locations = locations;
        this.audit = audit;
    }

    public record NewCategory(String code, String name, ProductFamily family, Tracking tracking, MakingType makingType,
                              BigDecimal makingValue, BigDecimal wastagePct, BigDecimal gstPct) {}

    public record CategoryChanges(String name, MakingType makingType, BigDecimal makingValue, BigDecimal wastagePct,
                                  BigDecimal gstPct, Boolean active) {}

    public List<Category> activeCategories() {
        return categories.findActive();
    }

    public List<Purity> activePurities() {
        return purities.findActive();
    }

    public List<Location> locations() {
        return locations.findAll();
    }

    public Category category(long id) {
        return categories.findById(id).orElseThrow(() -> BusinessException.notFound("Category not found"));
    }

    public Purity purity(Metal metal, String code) {
        return purities.find(metal, code).orElseThrow(() ->
                BusinessException.validation("Purity " + code + " is not set up for " + metal + "."));
    }

    public Location location(long id) {
        return locations.findById(id).orElseThrow(() -> BusinessException.notFound("Location not found"));
    }

    public Location defaultCounter() {
        return locations.findByCode(Location.DEFAULT_COUNTER)
                .orElseGet(() -> locations.findAll().stream().findFirst().orElseThrow());
    }

    @Transactional
    public Purity changePriceFactor(long purityId, BigDecimal factor) {
        CurrentUser.require(Permission.CONFIG);
        Purity p = purities.findById(purityId).orElseThrow(() -> BusinessException.notFound("Purity not found"));
        if (factor == null || factor.signum() <= 0 || factor.compareTo(MAX_FACTOR) > 0) {
            throw BusinessException.validation("Price factor must be between 0 and 2.");
        }
        purities.updatePriceFactor(purityId, factor);
        audit.record("PURITY_FACTOR", "purity", p.metal() + " " + p.code(), p.priceFactor() + " -> " + factor);
        return purities.findById(purityId).orElseThrow();
    }

    @Transactional
    public long createCategory(NewCategory c) {
        CurrentUser.require(Permission.CONFIG);
        if (c.code() == null || c.code().isBlank() || c.name() == null || c.name().isBlank()) {
            throw BusinessException.validation("Code and name are required.");
        }
        if (c.family() == null) throw BusinessException.validation("Choose the product family.");
        Category category = new Category(0, c.code().trim().toUpperCase(), c.name().trim(), c.family(), c.family().metal(),
                c.family().pricingMode(), c.tracking() == null ? Tracking.PIECE : c.tracking(), "QR",
                c.makingType() == null ? MakingType.PER_GRAM : c.makingType(), Decimals.orZero(c.makingValue()),
                Decimals.orZero(c.wastagePct()), c.gstPct() == null ? Decimals.of("3") : Decimals.round(c.gstPct()), true);
        long id = categories.insert(category);
        audit.record("CATEGORY_CREATE", "category", category.code(), null);
        return id;
    }

    @Transactional
    public void updateCategory(long id, CategoryChanges changes) {
        CurrentUser.require(Permission.CONFIG);
        Category c = category(id);
        categories.update(new Category(id, c.code(), changes.name() == null ? c.name() : changes.name(), c.family(), c.metal(),
                c.pricingMode(), c.tracking(), c.tagType(), changes.makingType() == null ? c.makingType() : changes.makingType(),
                Decimals.orZero(changes.makingValue()), Decimals.orZero(changes.wastagePct()), Decimals.orZero(changes.gstPct()),
                changes.active() == null || changes.active()));
        audit.record("CATEGORY_UPDATE", "category", c.code(), null);
    }
}
