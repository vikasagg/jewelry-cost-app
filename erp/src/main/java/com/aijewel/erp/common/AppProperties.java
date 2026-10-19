package com.aijewel.erp.common;

import org.springframework.boot.context.properties.ConfigurationProperties;

/** Deployment-level settings from application.yml (BRD §16). */
@ConfigurationProperties(prefix = "app")
public record AppProperties(
        String dataDir,
        String zone,
        String tokenSecret,
        int tokenHours,
        Platform platform,
        ControlDb controlDb,
        CloudPostgres cloudPostgres,
        Demo demo) {

    public record Platform(String username, String password) {}

    public record ControlDb(String url, String username, String password) {}

    public record CloudPostgres(String host, int port, String username, String password, String databasePrefix) {}

    public record Demo(boolean enabled, String storageMode) {}
}
