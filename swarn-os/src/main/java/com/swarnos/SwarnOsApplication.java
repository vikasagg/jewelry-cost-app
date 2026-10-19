package com.swarnos;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class SwarnOsApplication {
    public static void main(String[] args) {
        SpringApplication.run(SwarnOsApplication.class, args);
    }
}
