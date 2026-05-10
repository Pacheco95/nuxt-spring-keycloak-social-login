#!/usr/bin/env bash
# Stack-level smoke test (Tier 1): exercises the running social-login stack
# at the HTTP/JWT layer without a browser. Run via `make test-stack`.
#
# Verifies:
#   - All 6 services healthy/running
#   - Public endpoints (Keycloak discovery, JWKS, backend health, PgAdmin)
#   - BFF routes (/, /profile, /api/me, /auth/keycloak/login redirect, logout)
#   - Backend JWT validation against real Keycloak-issued tokens (via a
#     temporary direct-grant toggle on the nuxt-bff client)
#   - Realm-init idempotency (re-run hits all "already exists" branches)
#   - Realm contents (client config, mappers, IdP)
#   - Database connectivity + Flyway migrations
#   - Compose configuration (URL routing between browser and in-network)
#
# Browser-driven flows (the actual OAuth code dance, profile page render,
# logout button) are covered by the Playwright e2e suite — see e2e/.
set -uo pipefail

cd "$(dirname "$0")/.."

# Per-run scratch directory so concurrent invocations don't fight.
TMP_ROOT="${TMPDIR:-/tmp}/social-login-test-$$"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0; FAIL=0; FAILURES=()
assert() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf '  \033[32m✓\033[0m %s\n' "$name"
  else
    FAIL=$((FAIL + 1)); FAILURES+=("$name")
    printf '  \033[31m✗\033[0m %s\n' "$name"
  fi
}
section() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

if [ ! -f .env ]; then
  echo "ERROR: .env not found in repo root. Copy .env.example and fill in secrets." >&2
  exit 2
fi
set -a; . ./.env; set +a

kcadm() { docker exec social-login-keycloak-1 /opt/keycloak/bin/kcadm.sh "$@"; }
get_redirect() { curl -s -o /dev/null -w '%{redirect_url}' "$1"; }

# ─────────────────────────────────────────────────────────────────────────
section "1. Container health"
for s in keycloak-db backend-db keycloak; do
  assert "$s reports healthy" \
    test "$(docker inspect -f '{{.State.Health.Status}}' social-login-${s}-1 2>/dev/null)" = "healthy"
done
for s in backend frontend pgadmin; do
  assert "$s is running" \
    test "$(docker inspect -f '{{.State.Status}}' social-login-${s}-1 2>/dev/null)" = "running"
done

# ─────────────────────────────────────────────────────────────────────────
section "2. Public service endpoints"
assert "Keycloak OIDC discovery served from public URL" \
  curl -fsS http://localhost:8080/realms/social-login/.well-known/openid-configuration
assert "JWKS endpoint returns 200" \
  test "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/realms/social-login/protocol/openid-connect/certs)" = "200"
assert "Backend /actuator/health returns UP" \
  bash -c 'curl -fsS http://localhost:8081/actuator/health | grep -q UP'
assert "Backend /api/me unauthenticated returns 401" \
  test "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/api/me)" = "401"
assert "Backend /api/me with bogus bearer returns 401" \
  test "$(curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer not.a.jwt' http://localhost:8081/api/me)" = "401"
assert "Issuer claim matches expected (no issuer mismatch)" \
  bash -c 'curl -fsS http://localhost:8080/realms/social-login/.well-known/openid-configuration | grep -q "\"issuer\":\"http://localhost:8080/realms/social-login\""'
PG_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:5050/login)
assert "PgAdmin login page reachable" bash -c "[ $PG_CODE = 200 ] || [ $PG_CODE = 401 ]"

# ─────────────────────────────────────────────────────────────────────────
section "3. BFF routes (logged-out)"
assert "/ returns 200 (public)" \
  test "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/)" = "200"
assert "/ shows Login with Google button" \
  bash -c 'curl -sS http://localhost:3000/ | grep -q "Login with Google"'
assert "/profile redirects (fail-closed)" \
  bash -c "code=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/profile); [ \$code = 301 ] || [ \$code = 302 ]"
assert "/api/me proxy 401 without session" \
  test "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/api/me)" = "401"

LOGIN_LOC=$(get_redirect http://localhost:3000/auth/keycloak/login)
echo "$LOGIN_LOC" > "$TMP_ROOT/login_loc"
assert "/auth/keycloak/login → public Keycloak authorize" \
  grep -q 'localhost:8080/realms/social-login/protocol/openid-connect/auth' "$TMP_ROOT/login_loc"
assert "Login redirect carries PKCE S256" \
  grep -q 'code_challenge_method=S256' "$TMP_ROOT/login_loc"
assert "Login redirect carries client_id=nuxt-bff" \
  grep -q 'client_id=nuxt-bff' "$TMP_ROOT/login_loc"
assert "Login redirect_uri matches BFF callback (lib's partial encoding)" \
  grep -q 'redirect_uri=http:%2F%2Flocalhost:3000%2Fauth%2Fkeycloak%2Fcallback' "$TMP_ROOT/login_loc"
assert "Login passes openid+profile+email scopes" \
  grep -q 'scope=openid+profile+email' "$TMP_ROOT/login_loc"
assert "Login redirect includes nonce" grep -q 'nonce=' "$TMP_ROOT/login_loc"

CALLBACK_LOC=$(get_redirect 'http://localhost:3000/auth/keycloak/login?callbackRedirectUrl=/profile')
echo "$CALLBACK_LOC" > "$TMP_ROOT/cb_loc"
assert "Login with callbackRedirectUrl=/profile still routes to Keycloak" \
  grep -q 'localhost:8080/realms/social-login' "$TMP_ROOT/cb_loc"

LOGOUT_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/auth/keycloak/logout)
assert "/auth/keycloak/logout exists and 302s" bash -c "[ '$LOGOUT_CODE' = 302 ]"
LOGOUT_LOC=$(get_redirect 'http://localhost:3000/auth/keycloak/logout')
echo "$LOGOUT_LOC" > "$TMP_ROOT/lo_loc"
assert "Logout (no session) redirects home (correct behavior)" \
  grep -qE '^http://localhost:3000/?$' "$TMP_ROOT/lo_loc"

# ─────────────────────────────────────────────────────────────────────────
section "4. Backend JWT validation (real Keycloak-issued tokens)"
kcadm config credentials --server http://localhost:8080 --realm master \
  --user "$KEYCLOAK_ADMIN_USER" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null 2>&1
CLIENT_UUID=$(kcadm get clients -r social-login -q clientId=nuxt-bff 2>/dev/null \
  | grep -oE '"id"[[:space:]]*:[[:space:]]*"[a-f0-9-]{36}"' | head -1 | grep -oE '[a-f0-9-]{36}')
kcadm update "clients/$CLIENT_UUID" -r social-login -s directAccessGrantsEnabled=true >/dev/null 2>&1
kcadm create users -r social-login -s username=battletest -s enabled=true \
  -s emailVerified=true -s email=battletest@example.com -s firstName=Battle \
  -s lastName=Test >/dev/null 2>&1 || true
USER_UUID=$(kcadm get users -r social-login -q username=battletest 2>/dev/null \
  | grep -oE '"id"[[:space:]]*:[[:space:]]*"[a-f0-9-]{36}"' | head -1 | grep -oE '[a-f0-9-]{36}')
kcadm set-password -r social-login --username battletest --new-password battletest123 >/dev/null 2>&1
TOKEN=$(curl -fsS -X POST http://localhost:8080/realms/social-login/protocol/openid-connect/token \
  -d grant_type=password -d "client_id=nuxt-bff" \
  -d "client_secret=${KEYCLOAK_REALM_CLIENT_SECRET}" \
  -d 'username=battletest' -d 'password=battletest123' \
  -d 'scope=openid profile email' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)

if [ -n "$TOKEN" ]; then
  assert "Valid JWT → /api/me 200" \
    test "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" http://localhost:8081/api/me)" = "200"
  curl -sS -H "Authorization: Bearer $TOKEN" http://localhost:8081/api/me > "$TMP_ROOT/me"
  assert "Returned name matches user" grep -q '"name":"Battle Test"' "$TMP_ROOT/me"
  assert "Returned email matches user" grep -q '"email":"battletest@example.com"' "$TMP_ROOT/me"
  assert "Returned sub matches Keycloak user UUID" grep -q "\"sub\":\"$USER_UUID\"" "$TMP_ROOT/me"

  TAMPERED="${TOKEN%.*}.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  assert "Tampered signature → 401" \
    test "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TAMPERED" http://localhost:8081/api/me)" = "401"
  assert "Forged JWT (different alg) → 401" \
    test "$(curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.fake' http://localhost:8081/api/me)" = "401"

  EXPIRED_PAYLOAD=$(python3 -c 'import json,base64,time; p=json.dumps({"sub":"x","exp":int(time.time())-3600}); print(base64.urlsafe_b64encode(p.encode()).decode().rstrip("="))')
  assert "Token claiming expiry in the past → 401" \
    test "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer eyJhbGciOiJSUzI1NiJ9.${EXPIRED_PAYLOAD}.bad" http://localhost:8081/api/me)" = "401"
else
  FAIL=$((FAIL + 1)); FAILURES+=("Could not mint token — backend tests skipped")
  echo "  ✗ Could not mint token (KEYCLOAK_REALM_CLIENT_SECRET correct?)"
fi

# Cleanup
kcadm update "clients/$CLIENT_UUID" -r social-login -s directAccessGrantsEnabled=false >/dev/null 2>&1
[ -n "${USER_UUID:-}" ] && kcadm delete "users/$USER_UUID" -r social-login >/dev/null 2>&1

# ─────────────────────────────────────────────────────────────────────────
section "5. Realm bootstrap idempotency"
docker compose -f infra/docker-compose.yml --env-file .env \
  run --rm keycloak-realm-init > "$TMP_ROOT/reinit" 2>&1
assert "Re-run finds existing realm" \
  grep -q "Realm 'social-login' already exists" "$TMP_ROOT/reinit"
assert "Re-run finds existing client" \
  grep -q "Client 'nuxt-bff' already exists" "$TMP_ROOT/reinit"
assert "Re-run finds existing picture protocol mapper" \
  grep -q "'picture' protocol mapper already present" "$TMP_ROOT/reinit"
assert "Re-run finds existing Google IdP" \
  grep -q "Google identity provider already configured" "$TMP_ROOT/reinit"
assert "Re-run finds existing google-picture IdP mapper" \
  grep -q "'google-picture' IdP mapper already present" "$TMP_ROOT/reinit"
assert "Re-run completes successfully" \
  grep -q "fully bootstrapped" "$TMP_ROOT/reinit"

# ─────────────────────────────────────────────────────────────────────────
section "6. Realm contents"
kcadm config credentials --server http://localhost:8080 --realm master \
  --user "$KEYCLOAK_ADMIN_USER" --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null 2>&1
kcadm get realms/social-login > "$TMP_ROOT/realm" 2>/dev/null
kcadm get clients -r social-login -q clientId=nuxt-bff > "$TMP_ROOT/client" 2>/dev/null
assert "Realm 'social-login' exists" grep -q '"realm" : "social-login"' "$TMP_ROOT/realm"
assert "Client uses standard authorization flow" grep -q '"standardFlowEnabled" : true' "$TMP_ROOT/client"
assert "Direct grants are DISABLED on nuxt-bff" grep -q '"directAccessGrantsEnabled" : false' "$TMP_ROOT/client"
assert "Client is confidential (publicClient false)" grep -q '"publicClient" : false' "$TMP_ROOT/client"
assert "Client has PKCE S256 challenge configured" grep -q 'pkce.code.challenge.method' "$TMP_ROOT/client"

CLIENT_UUID2=$(grep -oE '"id" : "[a-f0-9-]{36}"' "$TMP_ROOT/client" | head -1 | grep -oE '[a-f0-9-]{36}')
kcadm get "clients/$CLIENT_UUID2/protocol-mappers/models" -r social-login > "$TMP_ROOT/cmappers" 2>/dev/null
assert "Client has 'picture' protocol mapper" grep -q '"name" : "picture"' "$TMP_ROOT/cmappers"

kcadm get identity-provider/instances/google -r social-login > "$TMP_ROOT/idp" 2>/dev/null
kcadm get identity-provider/instances/google/mappers -r social-login > "$TMP_ROOT/idpmappers" 2>/dev/null
assert "Google IdP is enabled" grep -q '"enabled" : true' "$TMP_ROOT/idp"
assert "Google IdP trustEmail is true" grep -q '"trustEmail" : true' "$TMP_ROOT/idp"
assert "Google IdP has google-picture attribute mapper" grep -q google-picture "$TMP_ROOT/idpmappers"

# ─────────────────────────────────────────────────────────────────────────
section "7. Database connectivity & migrations"
assert "Keycloak DB credentials accepted" \
  bash -c "docker exec social-login-keycloak-db-1 psql -U $KEYCLOAK_DB_USER -d $KEYCLOAK_DB_NAME -c 'SELECT 1' >/dev/null"
assert "Backend DB credentials accepted" \
  bash -c "docker exec social-login-backend-db-1 psql -U $BACKEND_DB_USER -d $BACKEND_DB_NAME -c 'SELECT 1' >/dev/null"
FLYWAY=$(docker exec social-login-backend-db-1 psql -U "$BACKEND_DB_USER" -d "$BACKEND_DB_NAME" -tAc 'SELECT count(*) FROM flyway_schema_history' 2>/dev/null)
assert "Backend Flyway migration applied" test "${FLYWAY:-0}" -ge 1

# ─────────────────────────────────────────────────────────────────────────
section "8. Compose configuration"
docker compose -f infra/docker-compose.yml --env-file .env config --format json > "$TMP_ROOT/compose" 2>/dev/null
GET_ENV='import json,sys; e=json.load(sys.stdin)["services"]["frontend"]["environment"]; print(e.get(sys.argv[1], ""))'
URL_AUTH=$(python3 -c "$GET_ENV" NUXT_OIDC_PROVIDERS_KEYCLOAK_AUTHORIZATION_URL < "$TMP_ROOT/compose")
URL_TOKEN=$(python3 -c "$GET_ENV" NUXT_OIDC_PROVIDERS_KEYCLOAK_TOKEN_URL < "$TMP_ROOT/compose")
URL_USERINFO=$(python3 -c "$GET_ENV" NUXT_OIDC_PROVIDERS_KEYCLOAK_USER_INFO_URL < "$TMP_ROOT/compose")
URL_LOGOUT=$(python3 -c "$GET_ENV" NUXT_OIDC_PROVIDERS_KEYCLOAK_LOGOUT_URL < "$TMP_ROOT/compose")
URL_BACKEND=$(python3 -c "$GET_ENV" NUXT_BACKEND_INTERNAL_URL < "$TMP_ROOT/compose")
assert "Auth URL set" test -n "$URL_AUTH"
assert "Token URL set" test -n "$URL_TOKEN"
assert "Userinfo URL set" test -n "$URL_USERINFO"
assert "Logout URL set" test -n "$URL_LOGOUT"
assert "Token endpoint resolves to in-network keycloak"     bash -c "[[ '$URL_TOKEN' == http://keycloak:* ]]"
assert "Userinfo endpoint resolves to in-network keycloak"  bash -c "[[ '$URL_USERINFO' == http://keycloak:* ]]"
assert "Authorization endpoint resolves to public localhost" bash -c "[[ '$URL_AUTH' == http://localhost:* ]]"
assert "Logout endpoint resolves to public localhost"       bash -c "[[ '$URL_LOGOUT' == http://localhost:* ]]"
assert "Backend internal URL is http://backend:8081"        test "$URL_BACKEND" = "http://backend:8081"

# ─────────────────────────────────────────────────────────────────────────
section "Summary"
TOTAL=$((PASS + FAIL))
printf '\n  %d / %d passed\n' "$PASS" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
  printf '\n\033[31mFailures:\033[0m\n'
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
