package com.swarnos.repair.domain;

/** A job with customer and karigar names, for screens. */
public record RepairJobView(RepairJob job, String customerName, String customerPhone, String karigarName) {}
