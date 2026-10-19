package com.swarnos.common.time;

import com.swarnos.common.config.AppProperties;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import org.springframework.stereotype.Component;

/** The shop's business date (India by default) and the current instant. */
@Component
public class BusinessClock {
    private final ZoneId zone;

    public BusinessClock(AppProperties props) {
        this.zone = ZoneId.of(props.zone() == null ? "Asia/Kolkata" : props.zone());
    }

    public LocalDate today() {
        return LocalDate.now(zone);
    }

    public Instant now() {
        return Instant.now();
    }
}
