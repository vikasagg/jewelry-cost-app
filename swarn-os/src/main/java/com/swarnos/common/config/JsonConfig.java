package com.swarnos.common.config;

import com.fasterxml.jackson.databind.cfg.CoercionAction;
import com.fasterxml.jackson.databind.cfg.CoercionInputShape;
import com.fasterxml.jackson.databind.type.LogicalType;
import org.springframework.boot.autoconfigure.jackson.Jackson2ObjectMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Blank form fields ("") arrive as null numbers, dates and flags instead of failing to parse. */
@Configuration
public class JsonConfig {
    @Bean
    Jackson2ObjectMapperBuilderCustomizer blankStringsAsNull() {
        return builder -> builder.postConfigurer(mapper -> {
            for (LogicalType t : new LogicalType[] {LogicalType.Integer, LogicalType.Float, LogicalType.Boolean,
                    LogicalType.DateTime, LogicalType.Enum}) {
                mapper.coercionConfigFor(t).setCoercion(CoercionInputShape.EmptyString, CoercionAction.AsNull);
            }
        });
    }
}
