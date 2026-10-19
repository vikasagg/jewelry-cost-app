package com.swarnos.parties;

import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/parties")
public class PartyController {
    private final PartyService parties;

    public PartyController(PartyService parties) {
        this.parties = parties;
    }

    @GetMapping
    public List<Map<String, Object>> list(@RequestParam(required = false) String type, @RequestParam(required = false) String q) {
        return parties.list(type == null ? null : type.toUpperCase(), q);
    }

    @GetMapping("/{id}")
    public Map<String, Object> get(@PathVariable long id) {
        return parties.get(id);
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, Object> body) {
        body.remove("id");
        return parties.save(body);
    }

    @PutMapping("/{id}")
    public Map<String, Object> update(@PathVariable long id, @RequestBody Map<String, Object> body) {
        body.put("id", id);
        return parties.save(body);
    }

    @PostMapping("/{id}/settle")
    public Map<String, Object> settle(@PathVariable long id, @RequestBody Map<String, Object> body) {
        return parties.settle(id, body);
    }
}
