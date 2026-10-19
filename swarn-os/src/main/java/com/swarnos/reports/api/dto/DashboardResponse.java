package com.swarnos.reports.api.dto;

import com.swarnos.accounting.domain.Book;
import com.swarnos.purchase.domain.DayTotals;
import com.swarnos.rates.service.RateService;
import com.swarnos.repair.domain.RepairStats;
import com.swarnos.reports.service.DashboardService;
import com.swarnos.sales.api.dto.SaleResponse;
import com.swarnos.sales.domain.SalesDayStats;
import com.swarnos.tally.domain.TallySession;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

public record DashboardResponse(LocalDate businessDate, RateService.TodayRates rate, SalesDayStats salesToday,
                                DayTotals purchasesToday, DashboardService.StockSummary stock, RepairStats repairs,
                                TallySession tally, Map<Book, BigDecimal> books, List<SaleResponse> recentSales,
                                List<String> alerts) {

    public static DashboardResponse of(DashboardService.Dashboard d) {
        return new DashboardResponse(d.businessDate(), d.rate(), d.salesToday(), d.purchasesToday(), d.stock(), d.repairs(),
                d.tally(), d.books(), d.recentSales().stream().map(SaleResponse::summary).toList(), d.alerts());
    }
}
