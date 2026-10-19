-- Control-plane database: tenant registry and routing only (no business data).
CREATE TABLE tenant (
    code          VARCHAR(40)  PRIMARY KEY,
    name          VARCHAR(200) NOT NULL,
    storage_mode  VARCHAR(10)  NOT NULL,          -- LOCAL | CLOUD
    jdbc_url      VARCHAR(500) NOT NULL,
    db_username   VARCHAR(100),
    db_password   VARCHAR(200),
    status        VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    plan          VARCHAR(40)  NOT NULL DEFAULT 'STANDARD',
    schema_version VARCHAR(20),
    created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);
