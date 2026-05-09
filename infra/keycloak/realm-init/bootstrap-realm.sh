#!/bin/sh
# Step-wise idempotent bootstrap. Each entity (realm, client, mappers, IdP)
# is checked before being created, so re-running the script after editing it
# will pick up newly-added steps without requiring a realm wipe.
#
# Sh + grep only — the Keycloak runtime image has no python/jq.
#
# Run via the keycloak-realm-init compose service; env vars come from the
# root .env file (passed through docker-compose.yml).
set -eu

KCADM=/opt/keycloak/bin/kcadm.sh
KEYCLOAK_URL="${KEYCLOAK_INTERNAL_URL}"
REALM="${KEYCLOAK_REALM_NAME}"

log() { printf '[realm-init] %s\n' "$*"; }

# ── Auth ─────────────────────────────────────────────────────────────────
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

# ── Realm ────────────────────────────────────────────────────────────────
if "$KCADM" get "realms/${REALM}" >/dev/null 2>&1; then
  log "Realm '${REALM}' already exists."
else
  log "Creating realm '${REALM}'."
  "$KCADM" create realms \
    -s "realm=${REALM}" \
    -s enabled=true \
    -s "displayName=${REALM}" \
    -s sslRequired=NONE \
    -s registrationAllowed=false \
    -s loginWithEmailAllowed=true \
    -s duplicateEmailsAllowed=false \
    -s resetPasswordAllowed=false \
    -s editUsernameAllowed=false \
    -s bruteForceProtected=true
fi

# ── BFF OIDC client ──────────────────────────────────────────────────────
# kcadm prints pretty JSON; grab the first UUID-shaped value following an
# "id" key. Reliable enough for our tightly-scoped queries.
get_first_uuid() {
  grep -oE '"id"[[:space:]]*:[[:space:]]*"[a-f0-9-]{36}"' \
    | head -n1 \
    | grep -oE '[a-f0-9-]{36}'
}

CLIENT_UUID=$("$KCADM" get clients -r "${REALM}" \
  -q "clientId=${KEYCLOAK_REALM_CLIENT_ID}" 2>/dev/null | get_first_uuid || true)

if [ -z "${CLIENT_UUID:-}" ]; then
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
  printf '%s' "$CLIENT_PAYLOAD" | "$KCADM" create clients -r "${REALM}" -f -
  CLIENT_UUID=$("$KCADM" get clients -r "${REALM}" \
    -q "clientId=${KEYCLOAK_REALM_CLIENT_ID}" | get_first_uuid)
else
  log "Client '${KEYCLOAK_REALM_CLIENT_ID}' already exists (uuid=${CLIENT_UUID})."
fi

# ── 'picture' protocol mapper on the BFF client ──────────────────────────
if "$KCADM" get "clients/${CLIENT_UUID}/protocol-mappers/models" -r "${REALM}" \
   2>/dev/null | grep -q '"name"[[:space:]]*:[[:space:]]*"picture"'; then
  log "'picture' protocol mapper already present on client."
else
  log "Adding 'picture' protocol mapper to client '${KEYCLOAK_REALM_CLIENT_ID}'."
  PICTURE_CLIENT_MAPPER=$(cat <<'JSON'
{
  "name": "picture",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-attribute-mapper",
  "config": {
    "user.attribute": "picture",
    "claim.name": "picture",
    "jsonType.label": "String",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true",
    "multivalued": "false",
    "aggregate.attrs": "false"
  }
}
JSON
)
  printf '%s' "$PICTURE_CLIENT_MAPPER" | "$KCADM" create \
    "clients/${CLIENT_UUID}/protocol-mappers/models" -r "${REALM}" -f -
fi

# ── Google IdP — needs credentials ───────────────────────────────────────
if [ -z "${GOOGLE_CLIENT_ID:-}" ] || [ -z "${GOOGLE_CLIENT_SECRET:-}" ]; then
  log "WARNING: GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET are blank."
  log "         Realm and client are configured, but the Google IdP is NOT."
  log "         Fill the values into .env, then run 'make realm-reset' to retry."
  exit 0
fi

if "$KCADM" get "identity-provider/instances/google" -r "${REALM}" >/dev/null 2>&1; then
  log "Google identity provider already configured."
else
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
    -r "${REALM}" -f -
fi

# ── 'picture' IdP mapper on Google ───────────────────────────────────────
if "$KCADM" get "identity-provider/instances/google/mappers" -r "${REALM}" \
   2>/dev/null | grep -q '"name"[[:space:]]*:[[:space:]]*"google-picture"'; then
  log "'google-picture' IdP mapper already present."
else
  log "Adding 'picture' attribute importer mapper to the Google IdP."
  PICTURE_IDP_MAPPER=$(cat <<'JSON'
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
  printf '%s' "$PICTURE_IDP_MAPPER" | "$KCADM" create \
    "identity-provider/instances/google/mappers" -r "${REALM}" -f -
fi

log "Done. Realm '${REALM}' is fully bootstrapped."
