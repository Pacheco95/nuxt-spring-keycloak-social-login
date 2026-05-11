CREATE TABLE users (
    id            UUID PRIMARY KEY,
    keycloak_sub  VARCHAR(255) NOT NULL UNIQUE,
    email         VARCHAR(255) UNIQUE,
    name          VARCHAR(255),
    picture       TEXT,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at    TIMESTAMP WITH TIME ZONE NOT NULL
);
