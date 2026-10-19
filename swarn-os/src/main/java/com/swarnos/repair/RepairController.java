package com.swarnos.repair;

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
@RequestMapping("/api/repairs")
public class RepairController {
    private final RepairService repairs;

    public RepairController(RepairService repairs) {
        this.repairs = repairs;
    }

    @GetMapping
    public List<Map<String, Object>> list(@RequestParam(required = false) String status, @RequestParam(required = false) String q) {
        return repairs.list(status == null ? null : status.toUpperCase(), q);
    }

    @GetMapping("/{id}")
    public Map<String, Object> get(@PathVariable long id) {
        return repairs.get(id);
    }

    /** Scan lookup by job number printed on the repair tag. */
    @GetMapping("/lookup")
    public Map<String, Object> byNo(@RequestParam String no) {
        return repairs.byNo(no);
    }

    @PostMapping
    public Map<String, Object> intake(@RequestBody Map<String, Object> body) {
        return repairs.intake(body);
    }

    @PostMapping("/{id}/status")
    public Map<String, Object> advance(@PathVariable long id, @RequestBody Map<String, Object> body) {
        return repairs.advance(id, body);
    }
}
