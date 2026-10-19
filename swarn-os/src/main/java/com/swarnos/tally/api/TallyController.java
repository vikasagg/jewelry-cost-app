package com.swarnos.tally.api;

import com.swarnos.tally.api.dto.OpenTallyRequest;
import com.swarnos.tally.api.dto.ReasonRequest;
import com.swarnos.tally.api.dto.ResolveVarianceRequest;
import com.swarnos.tally.api.dto.ScanRequest;
import com.swarnos.tally.api.dto.TallyResponse;
import com.swarnos.tally.service.TallyService;
import java.util.List;
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
    public List<TallyResponse> list() {
        return tally.list().stream().map(TallyResponse::row).toList();
    }

    @PostMapping
    public TallyResponse open(@RequestBody(required = false) OpenTallyRequest req) {
        OpenTallyRequest r = req == null ? new OpenTallyRequest(null, null, null) : req;
        return TallyResponse.of(tally.open(r.locationId(), r.categoryId(), r.notes()));
    }

    @GetMapping("/{id}")
    public TallyResponse get(@PathVariable long id) {
        return TallyResponse.of(tally.summary(id));
    }

    @PostMapping("/{id}/scan")
    public TallyResponse scan(@PathVariable long id, @RequestBody ScanRequest req) {
        TallyService.ScanResult result = tally.scan(id, req.allCodes());
        return TallyResponse.of(result.summary(), result.added());
    }

    @PostMapping("/{id}/unscan")
    public TallyResponse unscan(@PathVariable long id, @RequestBody ReasonRequest req) {
        return TallyResponse.of(tally.unscan(id, req.code()));
    }

    @PostMapping("/{id}/compare")
    public TallyResponse compare(@PathVariable long id) {
        return TallyResponse.of(tally.compare(id));
    }

    @PostMapping("/variance/{varianceId}")
    public TallyResponse resolve(@PathVariable long varianceId, @RequestBody ResolveVarianceRequest req) {
        return TallyResponse.of(tally.resolve(varianceId, req.resolution(), req.reason()));
    }

    @PostMapping("/{id}/close")
    public TallyResponse close(@PathVariable long id) {
        return TallyResponse.of(tally.close(id));
    }

    @PostMapping("/{id}/reopen")
    public TallyResponse reopen(@PathVariable long id, @RequestBody ReasonRequest req) {
        return TallyResponse.of(tally.reopen(id, req.reason()));
    }
}
