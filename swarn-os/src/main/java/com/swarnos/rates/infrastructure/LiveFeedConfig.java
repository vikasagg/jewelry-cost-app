package com.swarnos.rates.infrastructure;

/** Where a live rate feed is and which JSON fields hold the per-gram rates. */
public record LiveFeedConfig(String url, String goldField, String silverField, String platinumField) {}
