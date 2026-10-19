package com.aijewel.erp.search;

import java.util.Map;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class SearchController {
    private final SearchService search;

    public SearchController(SearchService search) {
        this.search = search;
    }

    /** Text from the browser's speech recognition, or typed. */
    @PostMapping("/api/search/ask")
    public Map<String, Object> ask(@RequestBody Map<String, String> body) {
        return search.ask(body.getOrDefault("text", ""));
    }
}
