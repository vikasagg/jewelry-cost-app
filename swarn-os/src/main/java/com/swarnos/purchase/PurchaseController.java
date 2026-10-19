package com.swarnos.purchase;

import com.swarnos.common.BusinessClock;
import com.swarnos.common.Rows;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/purchases")
public class PurchaseController {
    private final PurchaseService purchases;
    private final BusinessClock clock;

    public PurchaseController(PurchaseService purchases, BusinessClock clock) {
        this.purchases = purchases;
        this.clock = clock;
    }

    @GetMapping
    public List<Map<String, Object>> list(@RequestParam(required = false, name = "class") String purchaseClass,
                                          @RequestParam(required = false) String mode,
                                          @RequestParam(required = false) String from,
                                          @RequestParam(required = false) String to) {
        LocalDate t = to == null || to.isBlank() ? clock.today() : Rows.date(to);
        LocalDate f = from == null || from.isBlank() ? t.minusDays(30) : Rows.date(from);
        return purchases.list(purchaseClass, mode, f, t);
    }

    @GetMapping("/{id}")
    public Map<String, Object> get(@PathVariable long id) {
        return purchases.get(id);
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, Object> body) {
        return purchases.create(body);
    }

    @PutMapping("/{id}/class")
    public Map<String, Object> changeClass(@PathVariable long id, @RequestBody Map<String, String> body) {
        return purchases.changeClass(id, body.get("purchase_class"), body.get("reason"));
    }

    @PostMapping("/return-item/{itemId}")
    public Map<String, Object> returnItem(@PathVariable long itemId, @RequestBody Map<String, String> body) {
        return purchases.returnToVendor(itemId, body.get("reason"));
    }
}
