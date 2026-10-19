package com.swarnos;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

/**
 * Swarn-OS: multi-tenant jewellery store system.
 *
 * <p>Every feature module (rates, inventory, sales, ...) is split into four layers:
 * {@code api} (REST controllers and DTOs), {@code service} (business rules and
 * transactions), {@code domain} (entities, enums and pure rules) and
 * {@code repository} (SQL). The layering is enforced by {@code ArchitectureTest}.
 */
@SpringBootApplication
@ConfigurationPropertiesScan
public class SwarnOsApplication {
    public static void main(String[] args) {
        SpringApplication.run(SwarnOsApplication.class, args);
    }
}
