package com.aijewel.erp.rates;

import com.aijewel.erp.common.Num;
import java.util.List;
import java.util.Map;
import org.springframework.transaction.annotation.Transactional;
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

    public record ManualRate(Object gold24k, Object silver, Object platinum, Boolean approveNow, String note) {}

    @GetMapping("/today")
    public Map<String, Object> today() {
        return rates.today();
    }

    @GetMapping("/history")
    public List<Map<String, Object>> history() {
        return rates.history();
    }

    @GetMapping("/{id}")
    public Map<String, Object> get(@PathVariable long id) {
        return rates.get(id);
    }

    @PostMapping("/preview")
    public List<Map<String, Object>> preview(@RequestBody ManualRate r) {
        return rates.derive(Num.of(r.gold24k()), Num.of(r.silver()), Num.of(r.platinum()));
    }

    /** Morning entry by hand; the owner can save and approve in one step. */
    @PostMapping("/manual")
    @Transactional
    public Map<String, Object> manual(@RequestBody ManualRate r) {
        Map<String, Object> set = rates.propose("MANUAL", Num.of(r.gold24k()), Num.of(r.silver()), Num.of(r.platinum()),
                "Manual entry", r.note());
        if (Boolean.TRUE.equals(r.approveNow())) {
            return rates.approve(((Number) set.get("id")).longValue());
        }
        return set;
    }

    @PostMapping("/live")
    public Map<String, Object> live() {
        return rates.fetchLive();
    }

    @PostMapping("/{id}/approve")
    public Map<String, Object> approve(@PathVariable long id) {
        return rates.approve(id);
    }

    @PostMapping("/{id}/reject")
    public Map<String, Object> reject(@PathVariable long id) {
        return rates.reject(id);
    }
}
