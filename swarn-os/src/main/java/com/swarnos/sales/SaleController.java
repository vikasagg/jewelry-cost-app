package com.swarnos.sales;

import com.swarnos.common.BusinessClock;
import com.swarnos.common.Rows;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
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
    private final SaleService sales;
    private final BusinessClock clock;

    public SaleController(SaleService sales, BusinessClock clock) {
        this.sales = sales;
        this.clock = clock;
    }

    @GetMapping
    public List<Map<String, Object>> list(@RequestParam(required = false) String from, @RequestParam(required = false) String to,
                                          @RequestParam(required = false) String q) {
        LocalDate t = to == null || to.isBlank() ? clock.today() : Rows.date(to);
        LocalDate f = from == null || from.isBlank() ? t.minusDays(30) : Rows.date(from);
        return sales.list(f, t, q);
    }

    @GetMapping("/{id}")
    public Map<String, Object> get(@PathVariable long id) {
        return sales.get(id);
    }

    /** Live calculation while the bill is being built; saves nothing. */
    @PostMapping("/quote")
    public Map<String, Object> quote(@RequestBody Map<String, Object> body) {
        return sales.preview(body);
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, Object> body) {
        return sales.create(body);
    }

    @PostMapping("/{id}/return")
    public Map<String, Object> returnSale(@PathVariable long id, @RequestBody Map<String, String> body) {
        return sales.returnSale(id, body.get("reason"), body.get("refund_mode"));
    }
}
