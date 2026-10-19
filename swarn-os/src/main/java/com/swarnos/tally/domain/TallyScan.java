package com.swarnos.tally.domain;

import java.time.Instant;

public record TallyScan(long id, long sessionId, String code, Long itemId, String username, Instant scannedAt) {

    /** Scanned codes are compared in upper case without spaces. */
    public static String normalize(String code) {
        return code == null ? "" : code.trim().toUpperCase();
    }
}
