package com.swarnos.settings.api.dto;

import com.swarnos.settings.domain.MakingType;
import com.swarnos.settings.domain.ProductFamily;
import com.swarnos.settings.domain.Tracking;
import java.math.BigDecimal;

/** Create a category (no id) or update one (with id). */
public record CategoryRequest(Long id, String code, String name, ProductFamily family, Tracking tracking,
                              MakingType makingType, BigDecimal makingValue, BigDecimal wastagePct, BigDecimal gstPct,
                              Boolean active) {}
