package com.swarnos.repair.api;

import com.swarnos.repair.api.dto.RepairIntakeRequest;
import com.swarnos.repair.api.dto.RepairResponse;
import com.swarnos.repair.api.dto.RepairStatusRequest;
import com.swarnos.repair.service.RepairService;
import java.util.List;
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

    /** status: blank = all, OPEN = not delivered, or a status name. */
    @GetMapping
    public List<RepairResponse> list(@RequestParam(required = false) String status, @RequestParam(required = false) String q) {
        String filter = status == null || status.isBlank() ? null : status.toUpperCase();
        return repairs.list(filter, q).stream().map(RepairResponse::listed).toList();
    }

    @GetMapping("/{id}")
    public RepairResponse get(@PathVariable long id) {
        return RepairResponse.of(repairs.detail(id));
    }

    /** Scan lookup by the job number printed on the repair tag. */
    @GetMapping("/lookup")
    public RepairResponse byNumber(@RequestParam String no) {
        return RepairResponse.of(repairs.byNumber(no));
    }

    @PostMapping
    public RepairResponse intake(@RequestBody RepairIntakeRequest req) {
        return RepairResponse.of(repairs.intake(req.toIntake()));
    }

    @PostMapping("/{id}/status")
    public RepairResponse changeStatus(@PathVariable long id, @RequestBody RepairStatusRequest req) {
        return RepairResponse.of(repairs.changeStatus(id, req.toChange()));
    }
}
