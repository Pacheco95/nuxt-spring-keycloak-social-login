#!/bin/sh
# Writes a libpq passfile from env vars so PgAdmin can auto-connect to both
# DBs without prompting for a password. servers.json references /pgpass.
set -eu

PGPASS_FILE=/pgpass
{
  printf '%s:%s:%s:%s:%s\n' \
    "${KEYCLOAK_DB_HOST}" \
    "${KEYCLOAK_DB_PORT}" \
    "${KEYCLOAK_DB_NAME}" \
    "${KEYCLOAK_DB_USER}" \
    "${KEYCLOAK_DB_PASSWORD}"
  printf '%s:%s:%s:%s:%s\n' \
    "${BACKEND_DB_HOST}" \
    "${BACKEND_DB_PORT}" \
    "${BACKEND_DB_NAME}" \
    "${BACKEND_DB_USER}" \
    "${BACKEND_DB_PASSWORD}"
} > "$PGPASS_FILE"
chmod 600 "$PGPASS_FILE"

exec /entrypoint.sh "$@"
