package com.swarnos.repair.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonUnwrapped;
import com.swarnos.repair.domain.RepairEvent;
import com.swarnos.repair.domain.RepairJob;
import com.swarnos.repair.domain.RepairJobView;
import com.swarnos.repair.service.RepairService;
import java.math.BigDecimal;
import java.util.List;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record RepairResponse(@JsonUnwrapped RepairJob job, String customerName, String customerPhone, String karigarName,
                             BigDecimal metalDifference, BigDecimal karigarDifference, Boolean overdue, List<RepairEvent> events) {

    public static RepairResponse of(RepairService.RepairDetail d) {
        return of(d.view(), null, d.events());
    }

    public static RepairResponse listed(RepairService.ListedJob j) {
        return of(j.view(), j.overdue(), null);
    }

    private static RepairResponse of(RepairJobView v, Boolean overdue, List<RepairEvent> events) {
        RepairJob j = v.job();
        return new RepairResponse(j, v.customerName(), v.customerPhone(), v.karigarName(), j.metalDifference(),
                j.karigarDifference(), overdue, events);
    }
}
