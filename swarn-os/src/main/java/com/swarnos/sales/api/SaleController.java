package com.swarnos.sales.api;

import com.swarnos.common.api.DateRange;
import com.swarnos.common.time.BusinessClock;
import com.swarnos.sales.api.dto.ReturnSaleRequest;
import com.swarnos.sales.api.dto.SaleRequest;
import com.swarnos.sales.api.dto.SaleResponse;
import com.swarnos.sales.domain.BillQuote;
import com.swarnos.sales.service.SaleService;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/sales")
public class SaleController {
    private static final int DEFAULT_DAYS = 30;

    private final SaleService sales;
    private final BusinessClock clock;

    public SaleController(SaleService sales, BusinessClock clock) {
        this.sales = sales;
        this.clock = clock;
    }

    @GetMapping
    public List<SaleResponse> list(@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                                   @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
                                   @RequestParam(required = false) String q) {
        DateRange range = DateRange.lastDays(from, to, clock.today(), DEFAULT_DAYS);
        return sales.list(range.from(), range.to(), q).stream().map(SaleResponse::summary).toList();
    }

    @GetMapping("/{id}")
    public SaleResponse get(@PathVariable long id) {
        return SaleResponse.of(sales.detail(id), null);
    }

    /** Live calculation while the bill is being built; saves nothing. */
    @PostMapping("/quote")
    public BillQuote quote(@RequestBody SaleRequest req) {
        return sales.quote(req.toCommand());
    }

    @PostMapping
    public SaleResponse create(@RequestBody SaleRequest req) {
        SaleService.SaleResult result = sales.create(req.toCommand());
        return SaleResponse.of(result.detail(), result.warnings());
    }

    @PostMapping("/{id}/return")
    public SaleResponse returnSale(@PathVariable long id, @RequestBody ReturnSaleRequest req) {
        return SaleResponse.of(sales.returnSale(id, req.reason(), req.refundMode()), null);
    }
}
