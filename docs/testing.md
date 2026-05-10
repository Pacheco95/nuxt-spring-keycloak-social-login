# Testing

Two tiers, plus an optional manual smoke against real Google.

## Tier 1 — `make test-stack`

Bash script (`scripts/test-stack.sh`) that runs against the *already-running* stack and exercises 60 assertions over the HTTP / JWT layer:

- Container health for all 6 services
- Public service endpoints (Keycloak discovery, JWKS, backend health, PgAdmin)
- BFF routes when logged-out (`/`, `/profile`, `/api/me`, login redirect, logout redirect)
- Backend JWT validation against **real Keycloak-issued tokens** (briefly toggles direct grants on the `nuxt-bff` client, mints a token via password grant, verifies the backend accepts it, rejects tampered/forged/expired tokens, then reverts direct grants)
- Realm-init idempotency (re-runs the bootstrap, verifies every "already exists" branch fires)
- Realm contents (client config, mappers, IdP)
- Database connectivity + Flyway migrations
- Compose configuration (URL routing between browser-facing and in-network)

Fast (~30s), no browser, no internet. Good as a pre-commit / pre-PR smoke and as a CI gate.

## Tier 2 — `make test-e2e`

Browser-driven Playwright tests of the full user journey, end-to-end. The trick: Google is replaced by a **mock OIDC provider** (`infra/mock-google/`) inside the docker network. Keycloak still does identity brokering exactly as in production — the only difference is which IdP it talks to.

`infra/docker-compose.test.yml` overlays:
- `mock-google` — a tiny Node container running [`oauth2-mock-server`](https://github.com/axa-group/oauth2-mock-server). Issues ID tokens with Google-shaped claims (`email`, `email_verified`, `name`, `given_name`, `family_name`, `picture`) for a fixed fixture user. Auto-approves at `/authorize`. Serves a 1×1 transparent PNG so the avatar `<img>` actually loads.
- `keycloak-test-config` — one-shot that runs after `keycloak-realm-init` and **swaps** the `google` IdP. The original (production) IdP has `providerId: google` and is hardcoded to talk to `accounts.google.com`. The replacement uses `providerId: oidc` with the same alias, configured against the mock URLs. Same `kc_idp_hint=google` plumbing on the BFF side keeps working unchanged.

> ⚠️ **The swap persists in the `keycloak-db-data` volume.** `make test-e2e-down` and `make down` stop the containers but do not revert the realm — so a subsequent `make up` will still have `google` pointed at `http://localhost:9000`, and clicking Login from a browser will fail because `mock-google` is no longer running. To return to the production Google IdP, run `make realm-reset` (or `make clean` to wipe everything). See the README troubleshooting section for the full reproducer.

The hostname split is the same as the real Keycloak setup: the mock's `iss` claim is pinned to `http://localhost:9000` (browser-visible), but Keycloak fetches `/token`, `/userinfo`, and `/jwks` via the in-network compose service name `mock-google:9000`. See `CLAUDE.md` for the broader rationale.

Specs (`e2e/tests/`):

| Spec | Story | What it asserts |
|---|---|---|
| `01-login.spec.ts` | 001 + 002 | Click Login → land on `/profile` → name / email / picture all rendered, `<img>` actually decodes |
| `02-logout.spec.ts` | 003 | Click Log Out → home, `/profile` no longer accessible without re-auth |
| `03-session-persistence.spec.ts` | 004 | Reload `/profile` and home-and-back navigation keep the session |
| `04-error-display.spec.ts` | 005 | `?error=` query params render the right human-readable messages |

What this does NOT exercise: Google's actual UI, real Google's quirks, real ID-token structure differences, network failures of accounts.google.com. Those are the things you give up — and they're the same things that make a real-Google e2e flaky.

## Tier 3 — manual smoke against real Google (optional, pre-release)

The README's setup walkthrough has a real Google OAuth client. To smoke-test the full real chain:

1. `make up` (production stack, no test override).
2. Visit `http://localhost:3000`, click Login with Google.
3. Sign in with one of the Test users you registered in the OAuth consent screen.
4. Verify `/profile` renders.
5. Click Log Out, verify return to home.

Not automated. Worth running before each release; not worth running on every PR.

## Running

```bash
# Tier 1 against an already-up stack:
make up
make test-stack

# Tier 2 brings the test stack up itself:
make test-e2e
make test-e2e-down            # tear down when finished

# Both, in order:
make test
```

Playwright reports land in `e2e/playwright-report/` (HTML) on CI, or stream to the terminal locally.

## CI considerations

All three components — Docker, Bun, Playwright — are first-class on GitHub Actions runners:

- `docker/setup-buildx-action` for the compose build cache.
- `oven-sh/setup-bun` for Bun.
- `bunx playwright install --with-deps chromium` (already in the Makefile target).

A workflow that runs `make test` on every PR would catch ~95% of regressions automatically. The `make test-e2e-down` step is important so subsequent jobs don't see a stale mock IdP.
