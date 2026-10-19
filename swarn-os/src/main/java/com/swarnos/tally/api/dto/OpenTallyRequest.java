package com.swarnos.tally.api.dto;

public record OpenTallyRequest(Long locationId, Long categoryId, String notes) {}
