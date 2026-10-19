package com.swarnos.tally.service;

import com.swarnos.common.audit.service.AuditService;
import com.swarnos.common.error.BusinessException;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.inventory.domain.ItemStatus;
import com.swarnos.inventory.domain.MovementType;
import com.swarnos.inventory.domain.StockMove;
import com.swarnos.inventory.service.ItemService;
import com.swarnos.inventory.service.StockLedgerService;
import com.swarnos.repair.service.RepairService;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.settings.domain.SettingKeys;
import com.swarnos.settings.service.SettingsService;
import com.swarnos.tally.domain.RecentScan;
import com.swarnos.tally.domain.Resolution;
import com.swarnos.tally.domain.TallyItem;
import com.swarnos.tally.domain.TallyReconciliation;
import com.swarnos.tally.domain.TallyScan;
import com.swarnos.tally.domain.TallySession;
import com.swarnos.tally.domain.TallySessionView;
import com.swarnos.tally.domain.TallyStatus;
import com.swarnos.tally.domain.TallySummary;
import com.swarnos.tally.domain.TallyVariance;
import com.swarnos.tally.domain.VarianceKind;
import com.swarnos.tally.repository.TallyRepository;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Daily stock tally (BRD §5.2): open a session with the expected list, scan tags
 * (QR now, RFID bulk reads later through the same call), compare, decide each
 * variance with a reason, then close. Only an approved variance changes stock.
 */
@Service
public class TallyService {
    private static final int RECENT_SCANS = 15;

    private final TallyRepository tally;
    private final ItemService items;
    private final StockLedgerService stockLedger;
    private final RepairService repairs;
    private final SettingsService settings;
    private final AuditService audit;
    private final BusinessClock clock;

    public TallyService(TallyRepository tally, ItemService items, StockLedgerService stockLedger, RepairService repairs,
                        SettingsService settings, AuditService audit, BusinessClock clock) {
        this.tally = tally;
        this.items = items;
        this.stockLedger = stockLedger;
        this.repairs = repairs;
        this.settings = settings;
        this.audit = audit;
        this.clock = clock;
    }

    public record ScanResult(TallySummary summary, int added) {}

    @Transactional
    public TallySummary open(Long locationId, Long categoryId, String notes) {
        CurrentUser.require(Permission.TALLY_CAPTURE);
        long id = tally.insertSession(clock.today(), locationId, categoryId, CurrentUser.usernameOrSystem(), notes);
        List<Long> expected = items.inStockIds(locationId, categoryId);
        tally.insertExpected(id, expected);
        audit.record("TALLY_OPEN", "tally", id, "expected " + expected.size());
        return summary(id);
    }

    /** Records scanned codes; repeats inside a session are ignored, so staff can rescan freely. */
    @Transactional
    public ScanResult scan(long id, List<String> codes) {
        CurrentUser.require(Permission.TALLY_CAPTURE);
        requireOpen(id);
        int added = 0;
        for (String raw : codes) {
            String code = TallyScan.normalize(raw);
            if (code.isEmpty() || tally.scanExists(id, code)) continue;
            tally.insertScan(id, code, items.findIdByCode(code).orElse(null), CurrentUser.usernameOrSystem());
            added++;
        }
        return new ScanResult(summary(id), added);
    }

    @Transactional
    public TallySummary unscan(long id, String code) {
        CurrentUser.require(Permission.TALLY_CAPTURE);
        requireOpen(id);
        tally.deleteScan(id, TallyScan.normalize(code));
        return summary(id);
    }

    public TallySummary summary(long id) {
        TallySessionView view = tally.findView(id).orElseThrow(() -> BusinessException.notFound("Tally session not found"));
        return new TallySummary(view, reconcile(id), tally.findVariances(id), repairs.countInShop(), repairs.countWithKarigar(),
                recentScans(id));
    }

    /** Builds the review list: one variance per missing, unexpected or unknown tag. */
    @Transactional
    public TallySummary compare(long id) {
        CurrentUser.require(Permission.TALLY_CAPTURE);
        requireOpen(id);
        TallyReconciliation r = reconcile(id);
        tally.deleteOpenVariances(id);
        for (TallyItem m : r.missing()) addVariance(id, VarianceKind.MISSING, m.id(), m.tagCode());
        for (TallyItem u : r.unexpected()) addVariance(id, VarianceKind.UNEXPECTED, u.id(), u.tagCode());
        for (TallyScan s : r.unknown()) addVariance(id, VarianceKind.UNKNOWN, null, s.code());
        return summary(id);
    }

    /** Manager's decision: MARK_LOST posts a tally-loss movement; ACCEPTED keeps stock as is, with the reason on record. */
    @Transactional
    public TallySummary resolve(long varianceId, Resolution resolution, String reason) {
        CurrentUser.require(Permission.TALLY_APPROVE);
        TallyVariance v = tally.findVariance(varianceId).orElseThrow(() -> BusinessException.notFound("Variance not found"));
        requireOpen(v.sessionId());
        if (reason == null || reason.isBlank()) throw BusinessException.validation("Give a reason.");
        if (resolution == null) throw BusinessException.validation("Resolution must be MARK_LOST or ACCEPTED.");
        if (resolution == Resolution.MARK_LOST) {
            if (v.kind() != VarianceKind.MISSING) throw BusinessException.validation("Only a missing item can be marked lost.");
            stockLedger.post(new StockMove(v.itemId(), MovementType.TALLY_LOSS, -1, Set.of(ItemStatus.IN_STOCK), ItemStatus.LOST,
                    null, "TALLY", v.sessionId(), reason));
        }
        tally.resolveVariance(varianceId, resolution, reason.trim(), CurrentUser.usernameOrSystem(), clock.now());
        audit.record("TALLY_RESOLVE", "tally", v.sessionId(), v.kind() + " " + v.code() + " -> " + resolution + ": " + reason);
        return summary(v.sessionId());
    }

    @Transactional
    public TallySummary close(long id) {
        CurrentUser.require(Permission.TALLY_APPROVE);
        compare(id);
        long open = tally.countOpenVariances(id);
        if (open > 0 && settings.flag(SettingKeys.TALLY_STRICT_CLOSE, true)) {
            throw BusinessException.conflict(open + " variance(s) still need a decision before the tally can be closed.");
        }
        tally.close(id, CurrentUser.usernameOrSystem(), clock.now());
        audit.record("TALLY_CLOSE", "tally", id, "open variances " + open);
        return summary(id);
    }

    @Transactional
    public TallySummary reopen(long id, String reason) {
        CurrentUser.require(Permission.TALLY_APPROVE);
        if (reason == null || reason.isBlank()) throw BusinessException.validation("Give a reason to reopen.");
        TallySession s = tally.findView(id).orElseThrow(() -> BusinessException.notFound("Tally session not found")).session();
        if (s.status() != TallyStatus.CLOSED) throw BusinessException.conflict("Only a closed tally can be reopened.");
        tally.reopen(id);
        audit.record("TALLY_REOPEN", "tally", id, reason);
        return summary(id);
    }

    public List<TallySessionView> list() {
        return tally.list(100);
    }

    public Optional<TallySession> latest() {
        return tally.findLatest();
    }

    public long openSessions() {
        return tally.countByStatus(TallyStatus.OPEN);
    }

    public long sessionsToday() {
        return tally.countOn(clock.today());
    }

    private TallyReconciliation reconcile(long id) {
        List<Long> expectedIds = tally.findExpectedIds(id);
        List<TallyScan> scans = tally.findScans(id);
        Set<Long> expectedSet = new HashSet<>(expectedIds);
        Set<Long> extraIds = scans.stream().map(TallyScan::itemId).filter(i -> i != null && !expectedSet.contains(i))
                .collect(Collectors.toSet());
        return TallyReconciliation.of(items.listings(expectedIds), scans, items.listings(extraIds));
    }

    private List<RecentScan> recentScans(long id) {
        List<TallyScan> scans = tally.findScans(id);
        List<TallyScan> recent = scans.subList(Math.max(0, scans.size() - RECENT_SCANS), scans.size()).reversed();
        Map<Long, String> names = items.listings(recent.stream().map(TallyScan::itemId).filter(i -> i != null).collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(l -> l.item().id(), l -> l.item().name(), (a, b) -> a));
        return recent.stream().map(s -> new RecentScan(s.code(), s.scannedAt(), s.itemId() == null ? null : names.get(s.itemId())))
                .toList();
    }

    private void addVariance(long id, VarianceKind kind, Long itemId, String code) {
        if (!tally.varianceExists(id, kind, code)) tally.insertVariance(id, kind, itemId, code);
    }

    private void requireOpen(long id) {
        TallySession s = tally.findView(id).orElseThrow(() -> BusinessException.notFound("Tally session not found")).session();
        if (s.status() != TallyStatus.OPEN) throw BusinessException.conflict("This tally is closed.");
    }
}
