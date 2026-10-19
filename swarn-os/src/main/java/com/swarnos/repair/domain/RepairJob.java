package com.swarnos.repair.domain;

import com.swarnos.common.money.Decimals;
import com.swarnos.settings.domain.Metal;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

/** A customer's piece taken in for repair; weighed at every hand-off. */
public record RepairJob(long id, String jobNo, long customerId, String description, Metal metal, String purityCode,
                        BigDecimal weightIn, String itemCondition, String repairType, BigDecimal estimate, LocalDate promisedDate,
                        RepairStatus status, Long karigarId, BigDecimal weightIssued, BigDecimal weightReturned,
                        BigDecimal extraMetalWt, BigDecimal weightOut, BigDecimal charges, BigDecimal paid, String createdBy,
                        Instant createdAt, Instant deliveredAt) {

    /** Weight out minus weight in (gain is positive), once the piece is weighed out. */
    public BigDecimal metalDifference() {
        return weightOut == null ? null : Decimals.round(weightOut.subtract(weightIn));
    }

    /** What came back from the karigar minus what was issued. */
    public BigDecimal karigarDifference() {
        return weightReturned == null || weightIssued == null ? null : Decimals.round(weightReturned.subtract(weightIssued));
    }

    public boolean isOverdue(LocalDate today) {
        return status != RepairStatus.DELIVERED && promisedDate != null && promisedDate.isBefore(today);
    }
}
