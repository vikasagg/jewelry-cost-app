package com.aijewel.erp.tally;

import com.aijewel.erp.common.Rows;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/tally")
public class TallyController {
    private final TallyService tally;

    public TallyController(TallyService tally) {
        this.tally = tally;
    }

    @GetMapping
    public List<Map<String, Object>> list() {
        return tally.list();
    }

    @PostMapping
    public Map<String, Object> open(@RequestBody Map<String, Object> b) {
        return tally.open(Rows.idOrNull(b.get("location_id")), Rows.idOrNull(b.get("category_id")), Rows.strOrNull(b.get("notes")));
    }

    @GetMapping("/{id}")
    public Map<String, Object> get(@PathVariable long id) {
        return tally.summary(id);
    }

    /** Accepts one code, a list, or pasted text (one tag per line), e.g. a bulk read exported by a handheld. */
    @PostMapping("/{id}/scan")
    public Map<String, Object> scan(@PathVariable long id, @RequestBody Map<String, Object> b) {
        List<String> codes = new ArrayList<>();
        if (b.get("code") != null) codes.add(b.get("code").toString());
        if (b.get("codes") instanceof List<?> l) l.forEach(c -> codes.add(String.valueOf(c)));
        if (b.get("text") != null) codes.addAll(TallyService.splitCodes(b.get("text").toString()));
        return tally.scan(id, codes);
    }

    @PostMapping("/{id}/unscan")
    public Map<String, Object> unscan(@PathVariable long id, @RequestBody Map<String, String> b) {
        return tally.unscan(id, b.get("code"));
    }

    @PostMapping("/{id}/compare")
    public Map<String, Object> compare(@PathVariable long id) {
        return tally.compare(id);
    }

    @PostMapping("/variance/{varianceId}")
    public Map<String, Object> resolve(@PathVariable long varianceId, @RequestBody Map<String, String> b) {
        return tally.resolve(varianceId, b.get("resolution"), b.get("reason"));
    }

    @PostMapping("/{id}/close")
    public Map<String, Object> close(@PathVariable long id) {
        return tally.close(id);
    }

    @PostMapping("/{id}/reopen")
    public Map<String, Object> reopen(@PathVariable long id, @RequestBody Map<String, String> b) {
        return tally.reopen(id, b.get("reason"));
    }
}
