package com.swarnos.settings.service;

import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.common.money.Decimals;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.settings.domain.Setting;
import com.swarnos.settings.domain.SettingKeys;
import com.swarnos.settings.domain.ShopProfile;
import com.swarnos.settings.repository.SettingRepository;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Business settings stored per shop (BRD §16), with typed accessors for the other modules. */
@Service
public class SettingsService {
    private final SettingRepository repository;
    private final AuditService audit;
    private final BusinessClock clock;

    public SettingsService(SettingRepository repository, AuditService audit, BusinessClock clock) {
        this.repository = repository;
        this.audit = audit;
        this.clock = clock;
    }

    public List<Setting> all() {
        return repository.findAll();
    }

    public Optional<String> text(String key) {
        return repository.find(key).map(Setting::configValue).map(String::trim).filter(v -> !v.isEmpty());
    }

    public String text(String key, String fallback) {
        return text(key).orElse(fallback);
    }

    public BigDecimal decimal(String key, BigDecimal fallback) {
        return text(key).map(this::parse).orElse(fallback);
    }

    /** Blank means "no limit" (owner decision D-05). */
    public Optional<BigDecimal> limit(String key) {
        return text(key).map(this::parse);
    }

    public boolean flag(String key, boolean fallback) {
        return text(key).map("true"::equalsIgnoreCase).orElse(fallback);
    }

    public ShopProfile shopProfile() {
        return new ShopProfile(text(SettingKeys.SHOP_NAME, ""), text(SettingKeys.SHOP_ADDRESS, ""),
                text(SettingKeys.SHOP_PHONE, ""), text(SettingKeys.SHOP_GSTIN, ""));
    }

    /** Owner changes several settings at once; every change is audited. */
    @Transactional
    public int update(Map<String, String> values) {
        CurrentUser.require(Permission.CONFIG);
        values.forEach(this::write);
        return values.size();
    }

    /** Used while provisioning a shop (no signed-in user). */
    public void write(String key, String value) {
        String old = repository.find(key).map(Setting::configValue)
                .orElseThrow(() -> BusinessException.notFound("Unknown setting: " + key));
        repository.update(key, value, CurrentUser.usernameOrSystem(), clock.now());
        audit.record("CONFIG_CHANGE", "config", key, old + " -> " + value);
    }

    private BigDecimal parse(String v) {
        try {
            return Decimals.round(new BigDecimal(v.replace(",", "")));
        } catch (NumberFormatException e) {
            throw BusinessException.validation("Setting is not a number: " + v);
        }
    }
}
