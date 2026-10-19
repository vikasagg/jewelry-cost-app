package com.swarnos.search.api;

import com.swarnos.search.api.dto.AskRequest;
import com.swarnos.search.api.dto.AskResponse;
import com.swarnos.search.service.SearchService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class SearchController {
    private final SearchService search;

    public SearchController(SearchService search) {
        this.search = search;
    }

    @PostMapping("/api/search/ask")
    public AskResponse ask(@RequestBody AskRequest req) {
        return AskResponse.of(search.ask(req.text() == null ? "" : req.text()));
    }
}
