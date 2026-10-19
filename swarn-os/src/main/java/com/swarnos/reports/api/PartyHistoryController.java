package com.swarnos.reports.api;

import com.swarnos.reports.api.dto.PartyHistoryResponse;
import com.swarnos.reports.service.PartyHistoryService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

/** GET /api/parties/{id}: the party with its full history (a read model across modules). */
@RestController
public class PartyHistoryController {
    private final PartyHistoryService history;

    public PartyHistoryController(PartyHistoryService history) {
        this.history = history;
    }

    @GetMapping("/api/parties/{id}")
    public PartyHistoryResponse get(@PathVariable long id) {
        return PartyHistoryResponse.of(history.history(id));
    }
}
