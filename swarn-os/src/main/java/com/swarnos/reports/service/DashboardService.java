package com.swarnos.reports.service;

import com.swarnos.accounting.domain.Book;
import com.swarnos.accounting.service.LedgerService;
import com.swarnos.backup.service.BackupService;
import com.swarnos.common.money.Decimals;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.inventory.domain.Item;
import com.swarnos.inventory.service.ItemService;
import com.swarnos.purchase.domain.DayTotals;
import com.swarnos.purchase.service.PurchaseService;
import com.swarnos.rates.service.RateService;
import com.swarnos.repair.domain.RepairStats;
import com.swarnos.repair.service.RepairService;
import com.swarnos.sales.domain.SaleView;
import com.swarnos.sales.domain.SalesDayStats;
import com.swarnos.sales.service.SaleService;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import com.swarnos.tally.domain.TallySession;
import com.swarnos.tally.service.TallyService;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import org.springframework.stereotype.Service;

/** The owner's one-screen view of the day, assembled from the other modules. */
@Service
public class DashboardService {
    private static final int RECENT_BILLS = 6;

    private final RateService rates;
    private final SaleService sales;
    private final PurchaseService purchases;
    private final ItemService items;
    private final RepairService repairs;
    private final TallyService tally;
    private final LedgerService ledger;
    private final BackupService backups;
    private final BusinessClock clock;

    public DashboardService(RateService rates, SaleService sales, PurchaseService purchases, ItemService items,
                            RepairService repairs, TallyService tally, LedgerService ledger, BackupService backups,
                            BusinessClock clock) {
        this.rates = rates;
        this.sales = sales;
        this.purchases = purchases;
        this.items = items;
        this.repairs = repairs;
        this.tally = tally;
        this.ledger = ledger;
        this.backups = backups;
        this.clock = clock;
    }

    public record MetalStock(String metal, long pieces, BigDecimal netWt, BigDecimal value) {}

    public record StockSummary(long pieces, BigDecimal value, List<MetalStock> byMetal) {}

    public record Dashboard(LocalDate businessDate, RateService.TodayRates rate, SalesDayStats salesToday, DayTotals purchasesToday,
                            StockSummary stock, RepairStats repairs, TallySession tally, Map<Book, BigDecimal> books,
                            List<SaleView> recentSales, List<String> alerts) {}

    public Dashboard today() {
        LocalDate today = clock.today();
        RepairStats repairStats = repairs.stats();
        return new Dashboard(today, rates.today(), sales.statsToday(), purchases.totalsToday(), stock(), repairStats,
                tally.latest().orElse(null), CurrentUser.can(Permission.REPORTS_LEDGER) ? ledger.shopBalances() : null,
                sales.recent(RECENT_BILLS), alerts(today, repairStats));
    }

    private StockSummary stock() {
        Map<String, BigDecimal[]> byMetal = new TreeMap<>();
        long pieces = 0;
        BigDecimal value = Decimals.ZERO;
        for (ItemService.PricedItem p : items.inStock()) {
            Item i = p.listing().item();
            BigDecimal[] g = byMetal.computeIfAbsent(i.metal() == null ? "GIFTING" : i.metal().name(),
                    k -> new BigDecimal[] {BigDecimal.ZERO, Decimals.ZERO, Decimals.ZERO});
            g[0] = g[0].add(BigDecimal.valueOf(i.quantity()));
            g[1] = g[1].add(i.netWt());
            if (p.total() != null) {
                g[2] = g[2].add(p.total());
                value = value.add(p.total());
            }
            pieces += i.quantity();
        }
        List<MetalStock> metals = new ArrayList<>();
        byMetal.forEach((m, g) -> metals.add(new MetalStock(m, g[0].longValue(), Decimals.round(g[1]), Decimals.round(g[2]))));
        return new StockSummary(pieces, Decimals.round(value), metals);
    }

    private List<String> alerts(LocalDate today, RepairStats repairStats) {
        List<String> alerts = new ArrayList<>();
        if (rates.approvedToday().isEmpty()) alerts.add("Today's metal rate is not approved - billing is paused until it is.");
        long openTally = tally.openSessions();
        if (openTally > 0) alerts.add(openTally + " stock tally session(s) still open.");
        if (tally.sessionsToday() == 0) alerts.add("No stock tally done today yet.");
        if (repairStats.overdue() > 0) alerts.add(repairStats.overdue() + " repair job(s) are past their promised date.");
        int mismatches = items.ledgerCheck().size();
        if (mismatches > 0) alerts.add(mismatches + " item(s) differ from the stock ledger - check Inventory > Ledger check.");
        backups.lastBackupAt().ifPresentOrElse(at -> {
            long days = ChronoUnit.DAYS.between(at.atZone(ZoneId.systemDefault()).toLocalDate(), today);
            if (days > 1) alerts.add("Last backup was " + days + " days ago.");
        }, () -> alerts.add("No backup taken yet - take one to USB from Settings > Backup."));
        return alerts;
    }
}
