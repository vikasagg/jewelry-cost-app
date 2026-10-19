package com.swarnos.rates.service;

import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.rates.domain.BaseRates;
import com.swarnos.rates.domain.DailyRates;
import com.swarnos.rates.domain.RateDerivation;
import com.swarnos.rates.domain.RateLine;
import com.swarnos.rates.domain.RateSet;
import com.swarnos.rates.domain.RateSetStatus;
import com.swarnos.rates.domain.RateSetWithLines;
import com.swarnos.rates.domain.RateSource;
import com.swarnos.rates.infrastructure.LiveFeedConfig;
import com.swarnos.rates.infrastructure.LiveQuote;
import com.swarnos.rates.infrastructure.MetalRateProvider;
import com.swarnos.rates.repository.RateRepository;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.settings.domain.SettingKeys;
import com.swarnos.settings.service.MasterDataService;
import com.swarnos.settings.service.SettingsService;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Daily metal rate (BRD §6): base rates are entered by hand or proposed from a
 * live feed, approved once each morning, and that approved set prices every
 * bill of the day, online or offline.
 */
@Service
public class RateService {
    private final RateRepository repository;
    private final MasterDataService masters;
    private final SettingsService settings;
    private final AuditService audit;
    private final BusinessClock clock;
    private final List<MetalRateProvider> providers;

    public RateService(RateRepository repository, MasterDataService masters, SettingsService settings, AuditService audit,
                       BusinessClock clock, List<MetalRateProvider> providers) {
        this.repository = repository;
        this.masters = masters;
        this.settings = settings;
        this.audit = audit;
        this.clock = clock;
        this.providers = providers;
    }

    public record TodayRates(LocalDate businessDate, RateSetWithLines approved, List<RateSet> pending, RateSet lastApproved,
                             String liveProvider) {}

    // ---------- queries ----------

    public TodayRates today() {
        LocalDate today = clock.today();
        return new TodayRates(today, repository.findApproved(today).map(this::withLines).orElse(null),
                repository.findPending(today), repository.findLastApproved().orElse(null), liveProviderCode());
    }

    public List<RateSet> history() {
        return repository.history(120);
    }

    public List<RateSet> between(LocalDate from, LocalDate to) {
        return repository.between(from, to);
    }

    public RateSetWithLines get(long id) {
        return withLines(find(id));
    }

    public Optional<RateSet> approvedToday() {
        return repository.findApproved(clock.today());
    }

    /** Today's approved rates; billing waits until a rate is approved. */
    public DailyRates requireTodayRates() {
        return approvedToday().map(s -> dailyRates(s.id())).orElseThrow(() -> BusinessException.conflict(
                "Today's metal rate is not approved yet. Enter or approve it on the Rates screen first."));
    }

    public Optional<DailyRates> todayRatesIfApproved() {
        return approvedToday().map(s -> dailyRates(s.id()));
    }

    public DailyRates dailyRates(long rateSetId) {
        return new DailyRates(rateSetId, repository.findLines(rateSetId));
    }

    public List<RateLine> preview(BaseRates base) {
        return RateDerivation.derive(base.requireAllPositive(), masters.activePurities());
    }

    // ---------- commands ----------

    /** Morning entry by hand; the owner can save and approve in one step. */
    @Transactional
    public RateSetWithLines enterManual(BaseRates base, boolean approveNow, String note) {
        RateSet proposed = propose(RateSource.MANUAL, base, "Manual entry", note);
        return approveNow ? approve(proposed.id()) : withLines(proposed);
    }

    /** Asks the configured live source for a proposal. It never approves itself. */
    @Transactional
    public RateSetWithLines fetchLive() {
        String code = liveProviderCode();
        if (code.equals("NONE")) throw BusinessException.validation("No live rate source is configured. Enter the rate by hand.");
        MetalRateProvider provider = providers.stream().filter(p -> p.code().equals(code)).findFirst()
                .orElseThrow(() -> BusinessException.validation("Unknown live rate source: " + code));
        LiveFeedConfig config = new LiveFeedConfig(settings.text(SettingKeys.RATE_LIVE_URL, null),
                settings.text(SettingKeys.RATE_LIVE_GOLD_FIELD, "gold24k"), settings.text(SettingKeys.RATE_LIVE_SILVER_FIELD, "silver"),
                settings.text(SettingKeys.RATE_LIVE_PLATINUM_FIELD, "platinum"));
        LiveQuote quote = provider.fetch(config, repository.findLastApproved().map(RateSet::baseRates).orElse(null));
        return withLines(propose(RateSource.LIVE, quote.rates(), quote.provider(), "Live proposal - needs approval"));
    }

    @Transactional
    public RateSetWithLines approve(long id) {
        CurrentUser.require(Permission.RATE_APPROVE);
        RateSet set = find(id);
        if (set.status() != RateSetStatus.PROPOSED) throw BusinessException.conflict("Only a proposed rate can be approved.");
        if (!set.businessDate().equals(clock.today())) throw BusinessException.conflict("This proposal is for another day.");
        repository.supersedeApproved(set.businessDate());
        // Recalculated with the purity factors in force at approval time.
        repository.replaceLines(id, RateDerivation.derive(set.baseRates(), masters.activePurities()));
        repository.decide(id, RateSetStatus.APPROVED, CurrentUser.usernameOrSystem(), clock.now());
        audit.record("RATE_APPROVE", "rate_set", id, "gold24k=" + set.gold24k());
        return get(id);
    }

    @Transactional
    public RateSetWithLines reject(long id) {
        CurrentUser.require(Permission.RATE_APPROVE);
        if (!repository.decide(id, RateSetStatus.REJECTED, CurrentUser.usernameOrSystem(), clock.now())) {
            throw BusinessException.conflict("Only a proposed rate can be rejected.");
        }
        audit.record("RATE_REJECT", "rate_set", id, null);
        return get(id);
    }

    private RateSet propose(RateSource source, BaseRates base, String provider, String note) {
        CurrentUser.require(Permission.RATE_ENTER);
        base.requireAllPositive();
        RateSet draft = new RateSet(0, clock.today(), source, provider, base.gold24k(), base.silver(), base.platinum(),
                RateSetStatus.PROPOSED, CurrentUser.usernameOrSystem(), null, null, null, note);
        long id = repository.insert(draft);
        repository.replaceLines(id, RateDerivation.derive(base, masters.activePurities()));
        audit.record("RATE_PROPOSE", "rate_set", id, source + " gold24k=" + base.gold24k() + " silver=" + base.silver()
                + " pt=" + base.platinum());
        return find(id);
    }

    private RateSet find(long id) {
        return repository.findById(id).orElseThrow(() -> BusinessException.notFound("Rate set not found"));
    }

    private RateSetWithLines withLines(RateSet set) {
        return new RateSetWithLines(set, repository.findLines(set.id()));
    }

    private String liveProviderCode() {
        return settings.text(SettingKeys.RATE_LIVE_PROVIDER, "NONE");
    }
}
