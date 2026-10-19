package com.swarnos.parties.api;

import com.swarnos.parties.api.dto.PartyRequest;
import com.swarnos.parties.api.dto.PartyResponse;
import com.swarnos.parties.api.dto.SettleRequest;
import com.swarnos.parties.domain.Party;
import com.swarnos.parties.domain.PartyType;
import com.swarnos.parties.service.PartyService;
import java.math.BigDecimal;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Customers, vendors and karigars. A party's full history is served by PartyHistoryController. */
@RestController
@RequestMapping("/api/parties")
public class PartyController {
    private final PartyService parties;

    public PartyController(PartyService parties) {
        this.parties = parties;
    }

    @GetMapping
    public List<PartyResponse> search(@RequestParam(required = false) PartyType type, @RequestParam(required = false) String q) {
        return parties.search(type, q).stream().map(p -> PartyResponse.of(p.party(), p.balance())).toList();
    }

    @PostMapping
    public PartyResponse create(@RequestBody PartyRequest req) {
        return PartyResponse.of(parties.create(req.toDetails()), BigDecimal.ZERO);
    }

    @PutMapping("/{id}")
    public PartyResponse update(@PathVariable long id, @RequestBody PartyRequest req) {
        Party p = parties.update(id, req.toDetails());
        return PartyResponse.of(p, null);
    }

    @PostMapping("/{id}/settle")
    public PartyResponse settle(@PathVariable long id, @RequestBody SettleRequest req) {
        return PartyResponse.of(parties.settle(id, req.direction(), req.mode(), req.amount(), req.reference()), null);
    }
}
