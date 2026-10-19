package com.swarnos.items;

import static com.swarnos.common.Rows.strOrNull;

import com.swarnos.common.Num;
import com.swarnos.common.Rows;
import com.swarnos.stock.StockLedger;
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
@RequestMapping("/api/items")
public class ItemController {
    private final ItemService items;
    private final StockLedger ledger;

    public ItemController(ItemService items, StockLedger ledger) {
        this.items = items;
        this.ledger = ledger;
    }

    @GetMapping
    public List<Map<String, Object>> search(@RequestParam Map<String, String> p) {
        return items.search(new ItemService.ItemFilter(
                strOrNull(p.get("q")), p.getOrDefault("status", "IN_STOCK"), Rows.idOrNull(p.get("category_id")),
                strOrNull(p.get("family")), strOrNull(p.get("metal")), strOrNull(p.get("purity")),
                Rows.idOrNull(p.get("location_id")), Num.ofNullable(p.get("min_wt")), Num.ofNullable(p.get("max_wt")),
                Num.ofNullable(p.get("min_price")), Num.ofNullable(p.get("max_price")), strOrNull(p.get("purchase_class")),
                strOrNull(p.get("stone_type")), p.get("limit") == null ? null : Integer.parseInt(p.get("limit"))));
    }

    @GetMapping("/{id}")
    public Map<String, Object> get(@PathVariable long id) {
        return items.get(id);
    }

    /** Scan lookup: QR tag code today, RFID EPC later. */
    @GetMapping("/code/{code}")
    public Map<String, Object> byCode(@PathVariable String code) {
        return items.byCode(code);
    }

    @PostMapping
    public Map<String, Object> createOpening(@RequestBody Map<String, Object> body) {
        return items.createOpening(body);
    }

    @PutMapping("/{id}")
    public Map<String, Object> update(@PathVariable long id, @RequestBody Map<String, Object> body) {
        return items.update(id, body);
    }

    @PostMapping("/{id}/transfer/{locationId}")
    public Map<String, Object> transfer(@PathVariable long id, @PathVariable long locationId) {
        return items.transfer(id, locationId);
    }

    @GetMapping("/ledger-check")
    public List<Map<String, Object>> ledgerCheck() {
        return ledger.verify();
    }
}
