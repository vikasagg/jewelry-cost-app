package com.swarnos.common;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import org.springframework.stereotype.Component;

/** The shop's business date and time (India by default). */
@Component
public class BusinessClock {
    private final ZoneId zone;

    public BusinessClock(AppProperties props) {
        this.zone = ZoneId.of(props.zone() == null ? "Asia/Kolkata" : props.zone());
    }

    public LocalDate today() {
        return LocalDate.now(zone);
    }

    public LocalDateTime now() {
        return LocalDateTime.now(zone);
    }
}
