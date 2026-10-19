package com.swarnos.rates.api;

import com.swarnos.rates.api.dto.BaseRatesRequest;
import com.swarnos.rates.domain.RateLine;
import com.swarnos.rates.domain.RateSet;
import com.swarnos.rates.domain.RateSetWithLines;
import com.swarnos.rates.service.RateService;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/rates")
public class RateController {
    private final RateService rates;

    public RateController(RateService rates) {
        this.rates = rates;
    }

    @GetMapping("/today")
    public RateService.TodayRates today() {
        return rates.today();
    }

    @GetMapping("/history")
    public List<RateSet> history() {
        return rates.history();
    }

    @GetMapping("/{id}")
    public RateSetWithLines get(@PathVariable long id) {
        return rates.get(id);
    }

    @PostMapping("/preview")
    public List<RateLine> preview(@RequestBody BaseRatesRequest req) {
        return rates.preview(req.toBaseRates());
    }

    @PostMapping("/manual")
    public RateSetWithLines manual(@RequestBody BaseRatesRequest req) {
        return rates.enterManual(req.toBaseRates(), Boolean.TRUE.equals(req.approveNow()), req.note());
    }

    @PostMapping("/live")
    public RateSetWithLines live() {
        return rates.fetchLive();
    }

    @PostMapping("/{id}/approve")
    public RateSetWithLines approve(@PathVariable long id) {
        return rates.approve(id);
    }

    @PostMapping("/{id}/reject")
    public RateSetWithLines reject(@PathVariable long id) {
        return rates.reject(id);
    }
}
