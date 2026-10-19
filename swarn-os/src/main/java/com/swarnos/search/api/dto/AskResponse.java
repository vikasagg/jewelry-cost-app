package com.swarnos.search.api.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.swarnos.inventory.api.dto.ItemResponse;
import com.swarnos.repair.api.dto.RepairResponse;
import com.swarnos.search.domain.QueryInterpreter;
import com.swarnos.search.service.SearchService;
import java.math.BigDecimal;
import java.util.List;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record AskResponse(String query, String intent, List<String> chips, QueryInterpreter.Interpretation filters, String answer,
                          List<ItemResponse> results, List<RepairResponse> repairs, Integer count, BigDecimal totalValue,
                          BigDecimal totalNetWt) {

    public static AskResponse of(SearchService.Answer a) {
        return new AskResponse(a.query(), a.intent(), a.chips(), a.filters(), a.answer(),
                a.results().stream().map(ItemResponse::of).toList(),
                a.repairs() == null ? null : a.repairs().stream().map(RepairResponse::listed).toList(),
                a.count(), a.totalValue(), a.totalNetWt());
    }
}
