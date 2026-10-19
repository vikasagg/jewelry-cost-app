package com.swarnos.repair.api.dto;

import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.repair.domain.RepairStatus;
import com.swarnos.repair.service.RepairService;
import java.math.BigDecimal;

public record RepairStatusRequest(RepairStatus status, Long karigarId, BigDecimal weight, BigDecimal extraMetalWt,
                                  BigDecimal charges, BigDecimal amount, PaymentMode mode, String reference, String note) {

    public RepairService.StatusChange toChange() {
        return new RepairService.StatusChange(status, karigarId, weight, extraMetalWt, charges, amount, mode, reference, note);
    }
}
