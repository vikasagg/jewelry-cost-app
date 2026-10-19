package com.swarnos.parties.api.dto;

import com.swarnos.parties.domain.PartyDetails;
import com.swarnos.parties.domain.PartyType;
import java.time.LocalDate;

public record PartyRequest(PartyType partyType, String name, String phone, String email, String address, String gstin,
                           String pan, String idProof, LocalDate birthday, LocalDate anniversary, String notes) {

    public PartyDetails toDetails() {
        return new PartyDetails(partyType, name, phone, email, address, gstin, pan, idProof, birthday, anniversary, notes);
    }
}
