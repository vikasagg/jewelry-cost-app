package com.swarnos.parties.domain;

import com.swarnos.common.error.BusinessException;
import java.time.LocalDate;

/** Editable fields of a party, normalised (trimmed, GSTIN/PAN upper-case). */
public record PartyDetails(PartyType partyType, String name, String phone, String email, String address, String gstin,
                           String pan, String idProof, LocalDate birthday, LocalDate anniversary, String notes) {

    public PartyDetails {
        if (partyType == null) throw BusinessException.validation("Party type must be CUSTOMER, VENDOR or KARIGAR.");
        if (name == null || name.isBlank()) throw BusinessException.validation("Name is required.");
        name = name.trim();
        phone = blankToNull(phone);
        email = blankToNull(email);
        address = blankToNull(address);
        gstin = upper(gstin);
        pan = upper(pan);
        idProof = blankToNull(idProof);
        notes = blankToNull(notes);
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static String upper(String s) {
        String v = blankToNull(s);
        return v == null ? null : v.toUpperCase();
    }
}
