package com.swarnos.parties.api.dto;

import com.fasterxml.jackson.annotation.JsonUnwrapped;
import com.swarnos.parties.domain.Party;
import com.swarnos.security.CurrentUser;
import com.swarnos.security.Permission;
import java.math.BigDecimal;

/** A party with its account balance; ID proof is masked for roles without cost access. */
public record PartyResponse(@JsonUnwrapped Party party, BigDecimal balance) {
    private static final int VISIBLE_DIGITS = 4;

    public static PartyResponse of(Party p, BigDecimal balance) {
        return new PartyResponse(mask(p), balance);
    }

    public static Party mask(Party p) {
        String id = p.idProof();
        if (id == null || id.length() <= VISIBLE_DIGITS || CurrentUser.can(Permission.VIEW_COST)) return p;
        return new Party(p.id(), p.partyType(), p.name(), p.phone(), p.email(), p.address(), p.gstin(), p.pan(),
                "XXXX" + id.substring(id.length() - VISIBLE_DIGITS), p.birthday(), p.anniversary(), p.notes(), p.createdAt());
    }
}
