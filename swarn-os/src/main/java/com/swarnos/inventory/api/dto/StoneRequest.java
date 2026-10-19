package com.swarnos.inventory.api.dto;

import com.swarnos.inventory.domain.NewStone;
import java.math.BigDecimal;

public record StoneRequest(String stoneType, Integer pieces, BigDecimal carat, BigDecimal ratePerCarat, BigDecimal value,
                           String clarity, String colour, String certificate) {

    public NewStone toNewStone() {
        return new NewStone(stoneType, pieces, carat, ratePerCarat, value, clarity, colour, certificate);
    }
}
