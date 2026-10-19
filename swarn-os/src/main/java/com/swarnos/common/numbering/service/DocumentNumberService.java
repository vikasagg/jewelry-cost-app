package com.swarnos.common.numbering.service;

import com.swarnos.common.numbering.repository.DocumentSequenceRepository;
import java.time.LocalDate;
import org.springframework.stereotype.Service;

/** Gap-free document numbers per series and financial year, e.g. INV/2026-27/000001. */
@Service
public class DocumentNumberService {
    private final DocumentSequenceRepository sequences;

    public DocumentNumberService(DocumentSequenceRepository sequences) {
        this.sequences = sequences;
    }

    public String next(String prefix, LocalDate date) {
        String series = prefix + "/" + financialYear(date);
        return series + "/" + String.format("%06d", sequences.next(series));
    }

    public String nextTagCode(String prefix) {
        return prefix + String.format("%06d", sequences.next("TAG"));
    }

    static String financialYear(LocalDate d) {
        int start = d.getMonthValue() >= 4 ? d.getYear() : d.getYear() - 1;
        return start + "-" + String.format("%02d", (start + 1) % 100);
    }
}
