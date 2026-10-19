package com.swarnos.tally.api.dto;

import java.util.ArrayList;
import java.util.List;

/** One code, a list, or pasted text (one tag per line, e.g. a bulk read exported by a handheld). */
public record ScanRequest(String code, List<String> codes, String text) {

    public List<String> allCodes() {
        List<String> out = new ArrayList<>();
        if (code != null) out.add(code);
        if (codes != null) out.addAll(codes);
        if (text != null) {
            for (String c : text.split("[\\s,;]+")) if (!c.isBlank()) out.add(c);
        }
        return out;
    }
}
