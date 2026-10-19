package com.swarnos.reports.api;

import com.swarnos.reports.api.dto.DashboardResponse;
import com.swarnos.reports.service.DashboardService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class DashboardController {
    private final DashboardService dashboard;

    public DashboardController(DashboardService dashboard) {
        this.dashboard = dashboard;
    }

    @GetMapping("/api/dashboard")
    public DashboardResponse today() {
        return DashboardResponse.of(dashboard.today());
    }
}
