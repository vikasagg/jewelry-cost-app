package com.swarnos.tally.api.dto;

import com.swarnos.tally.domain.Resolution;

public record ResolveVarianceRequest(Resolution resolution, String reason) {}
