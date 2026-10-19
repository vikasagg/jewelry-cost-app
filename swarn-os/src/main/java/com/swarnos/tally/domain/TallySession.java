package com.swarnos.tally.domain;

import java.time.Instant;
import java.time.LocalDate;

public record TallySession(long id, LocalDate businessDate, Long locationId, Long categoryId, TallyStatus status,
                           int expectedCount, String openedBy, Instant openedAt, String closedBy, Instant closedAt, String notes) {}
