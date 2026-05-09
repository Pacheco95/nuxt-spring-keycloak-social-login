#!/bin/sh
# Idempotent bootstrap: creates the realm, the BFF OIDC client, and the Google
# identity provider. Safe to re-run — exits 0 if the realm already exists.
#
# Run via the keycloak-realm-init compose service. Required env vars come
# from the root .env file (passed through docker-compose.yml).
set -eu

KCADM=/opt/keycloak/bin/kcadm.sh
KEYCLOAK_URL="${KEYCLOAK_INTERNAL_URL}"

log() { printf '[realm-init] %s\n' "$*"; }

# Wait until Keycloak's admin endpoint accepts our credentials. depends_on:
# service_healthy should already cover this, but kcadm-based retry costs
# nothing and avoids relying on the healthcheck timing.
log "Authenticating against ${KEYCLOAK_URL} as ${KEYCLOAK_ADMIN_USER} ..."
attempts=0
until "$KCADM" config credentials \
        --server "${KEYCLOAK_URL}" \
        --realm master \
        --user "${KEYCLOAK_ADMIN_USER}" \
        --password "${KEYCLOAK_ADMIN_PASSWORD}" \
        >/dev/null 2>&1; do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge 60 ]; then
    log "ERROR: could not authenticate after 60 attempts. Aborting."
    exit 1
  fi
  log "  not ready yet (attempt ${attempts}), retrying in 3s ..."
  sleep 3
done
log "Authenticated."

# Idempotency: skip the whole bootstrap if the realm already exists.
if "$KCADM" get "realms/${KEYCLOAK_REALM_NAME}" >/dev/null 2>&1; then
  log "Realm '${KEYCLOAK_REALM_NAME}' already exists. Nothing to do."
  exit 0
fi

log "Creating realm '${KEYCLOAK_REALM_NAME}'."
"$KCADM" create realms \
  -s "realm=${KEYCLOAK_REALM_NAME}" \
  -s enabled=true \
  -s "displayName=${KEYCLOAK_REALM_NAME}" \
  -s sslRequired=NONE \
  -s registrationAllowed=false \
  -s loginWithEmailAllowed=true \
  -s duplicateEmailsAllowed=false \
  -s resetPasswordAllowed=false \
  -s editUsernameAllowed=false \
  -s bruteForceProtected=true

log "Creating OIDC client '${KEYCLOAK_REALM_CLIENT_ID}' for the Nuxt BFF."
CLIENT_PAYLOAD=$(cat <<JSON
{
  "clientId": "${KEYCLOAK_REALM_CLIENT_ID}",
  "secret": "${KEYCLOAK_REALM_CLIENT_SECRET}",
  "name": "Nuxt BFF",
  "enabled": true,
  "publicClient": false,
  "protocol": "openid-connect",
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": false,
  "serviceAccountsEnabled": false,
  "frontchannelLogout": false,
  "redirectUris": ["${FRONTEND_OIDC_REDIRECT_URI}"],
  "webOrigins": ["${FRONTEND_PUBLIC_URL}"],
  "attributes": {
    "post.logout.redirect.uris": "${FRONTEND_OIDC_POST_LOGOUT_REDIRECT_URI}",
    "pkce.code.challenge.method": "S256",
    "backchannel.logout.session.required": "true"
  }
}
JSON
)
printf '%s' "$CLIENT_PAYLOAD" | "$KCADM" create clients -r "${KEYCLOAK_REALM_NAME}" -f -

# Google identity provider — only configured if credentials are present, so
# the first compose-up still succeeds before the developer has filled in
# their Google Cloud values. Re-run with `make realm-reset` once they do.
if [ -z "${GOOGLE_CLIENT_ID:-}" ] || [ -z "${GOOGLE_CLIENT_SECRET:-}" ]; then
  log "WARNING: GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET are blank."
  log "         Realm and client created, but Google IdP is NOT configured."
  log "         Fill them into .env, then run 'make realm-reset' to retry."
  exit 0
fi

log "Adding Google identity provider."
GOOGLE_PAYLOAD=$(cat <<JSON
{
  "alias": "google",
  "displayName": "Google",
  "providerId": "google",
  "enabled": true,
  "trustEmail": true,
  "storeToken": false,
  "addReadTokenRoleOnCreate": false,
  "config": {
    "clientId": "${GOOGLE_CLIENT_ID}",
    "clientSecret": "${GOOGLE_CLIENT_SECRET}",
    "syncMode": "IMPORT",
    "useJwksUrl": "true"
  }
}
JSON
)
printf '%s' "$GOOGLE_PAYLOAD" | "$KCADM" create identity-provider/instances \
  -r "${KEYCLOAK_REALM_NAME}" -f -

log "Done. Realm '${KEYCLOAK_REALM_NAME}' bootstrapped successfully."
