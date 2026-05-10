#!/bin/sh
# Test-only Keycloak config patch: replaces the production Google IdP with one
# that points at the in-network mock-google service. Same alias ("google") so
# the BFF login button (kc_idp_hint=google) keeps working unchanged. Idempotent
# — safe to re-run on every `make test-e2e`.
#
# Required env (passed by docker-compose.test.yml):
#   KEYCLOAK_INTERNAL_URL     http://keycloak:8080
#   KEYCLOAK_ADMIN_USER, KEYCLOAK_ADMIN_PASSWORD
#   KEYCLOAK_REALM_NAME       social-login
#   MOCK_GOOGLE_PUBLIC_URL    http://localhost:9000  (browser-facing)
#   MOCK_GOOGLE_INTERNAL_URL  http://mock-google:9000 (in-network)
set -eu

KCADM=/opt/keycloak/bin/kcadm.sh
REALM="${KEYCLOAK_REALM_NAME}"
log() { printf '[test-config] %s\n' "$*"; }

# ── Auth ─────────────────────────────────────────────────────────────────
log "Authenticating against ${KEYCLOAK_INTERNAL_URL} ..."
attempts=0
until "$KCADM" config credentials \
        --server "${KEYCLOAK_INTERNAL_URL}" \
        --realm master \
        --user "${KEYCLOAK_ADMIN_USER}" \
        --password "${KEYCLOAK_ADMIN_PASSWORD}" \
        >/dev/null 2>&1; do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge 60 ]; then
    log "ERROR: could not authenticate after 60 attempts."; exit 1
  fi
  sleep 2
done
log "Authenticated."

# ── Wait for mock-google to be reachable (Keycloak fetches JWKS at IdP add) ──
log "Waiting for mock-google at ${MOCK_GOOGLE_INTERNAL_URL} ..."
attempts=0
until "$KCADM" get serverinfo >/dev/null 2>&1 && \
      ( wget -qO- "${MOCK_GOOGLE_INTERNAL_URL}/.well-known/openid-configuration" >/dev/null 2>&1 \
        || curl -fsS "${MOCK_GOOGLE_INTERNAL_URL}/.well-known/openid-configuration" >/dev/null 2>&1 ); do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge 30 ]; then
    log "WARNING: could not confirm mock-google reachability after 30 tries; proceeding anyway."
    break
  fi
  sleep 2
done
log "Mock-google reachable."

# ── Drop the existing google IdP (regardless of providerId) so we can swap it ─
if "$KCADM" get "identity-provider/instances/google" -r "${REALM}" >/dev/null 2>&1; then
  log "Removing existing 'google' IdP so it can be re-created against the mock."
  "$KCADM" delete "identity-provider/instances/google" -r "${REALM}"
fi

# ── Recreate as a generic OIDC IdP pointing at the mock ─────────────────
log "Creating mock-backed 'google' IdP (providerId=oidc, alias=google)."
PAYLOAD=$(cat <<JSON
{
  "alias": "google",
  "displayName": "Google (mock)",
  "providerId": "oidc",
  "enabled": true,
  "trustEmail": true,
  "storeToken": false,
  "addReadTokenRoleOnCreate": false,
  "config": {
    "clientId": "mock-google-client",
    "clientSecret": "mock-google-secret",
    "clientAuthMethod": "client_secret_post",
    "authorizationUrl": "${MOCK_GOOGLE_PUBLIC_URL}/authorize",
    "tokenUrl": "${MOCK_GOOGLE_INTERNAL_URL}/token",
    "userInfoUrl": "${MOCK_GOOGLE_INTERNAL_URL}/userinfo",
    "jwksUrl": "${MOCK_GOOGLE_INTERNAL_URL}/jwks",
    "issuer": "${MOCK_GOOGLE_PUBLIC_URL}",
    "validateSignature": "true",
    "useJwksUrl": "true",
    "syncMode": "IMPORT",
    "defaultScope": "openid profile email",
    "pkceEnabled": "false"
  }
}
JSON
)
printf '%s' "$PAYLOAD" | "$KCADM" create identity-provider/instances \
  -r "${REALM}" -f -

# ── Re-add the picture attribute importer (drops with the IdP) ──────────
log "Adding 'google-picture' attribute importer mapper."
PIC_MAPPER=$(cat <<'JSON'
{
  "name": "google-picture",
  "identityProviderAlias": "google",
  "identityProviderMapper": "oidc-user-attribute-idp-mapper",
  "config": {
    "syncMode": "INHERIT",
    "claim": "picture",
    "user.attribute": "picture"
  }
}
JSON
)
printf '%s' "$PIC_MAPPER" | "$KCADM" create \
  "identity-provider/instances/google/mappers" -r "${REALM}" -f -

log "Done. Realm '${REALM}' now brokers 'google' to the mock IdP."
