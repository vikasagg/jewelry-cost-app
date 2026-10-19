package com.swarnos.parties.domain;

import java.time.Instant;
import java.time.LocalDate;

/** A customer, vendor or karigar (job worker). */
public record Party(long id, PartyType partyType, String name, String phone, String email, String address, String gstin,
                    String pan, String idProof, LocalDate birthday, LocalDate anniversary, String notes, Instant createdAt) {

    public boolean hasPan() {
        return pan != null && !pan.isBlank();
    }
}
