package com.swarnos.repair.api.dto;

import com.swarnos.accounting.domain.PaymentMode;
import com.swarnos.repair.service.RepairService;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;
import java.time.LocalDate;

public record RepairIntakeRequest(Long customerId, String description, Metal metal, String purityCode, BigDecimal weightIn,
                                  String itemCondition, String repairType, BigDecimal estimate, LocalDate promisedDate,
                                  BigDecimal advance, PaymentMode advanceMode) {

    public RepairService.Intake toIntake() {
        return new RepairService.Intake(customerId, description, metal, purityCode, weightIn, itemCondition, repairType, estimate,
                promisedDate, advance, advanceMode);
    }
}
