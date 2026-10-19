package com.swarnos.settings.domain;

import java.math.BigDecimal;

/**
 * A purity of a metal. {@code priceFactor} is the share of the base rate used for
 * the selling price (22K = 0.92, decision D-01); {@code fineness} is the true
 * metal content used for fine weight in the metal books.
 */
public record Purity(long id, Metal metal, String code, BigDecimal priceFactor, BigDecimal fineness, int sortOrder,
                     boolean active) {}
