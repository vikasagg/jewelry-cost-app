package com.swarnos.settings.api.dto;

import com.swarnos.settings.domain.Category;
import com.swarnos.settings.domain.Location;
import com.swarnos.settings.domain.Purity;
import java.util.List;

public record MastersResponse(List<Category> categories, List<Purity> purities, List<Location> locations) {}
