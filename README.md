# Social Login (Keycloak-brokered Google OAuth)

A full-stack reference implementation of Google sign-in using **Keycloak 26 as an identity broker** in front of a **Spring Boot 4 / Kotlin 2.2** backend and a **Nuxt 4 SSR** frontend acting as a **BFF**. Tokens never reach the browser — only an HttpOnly session cookie does.

```
browser ──cookie──▶ Nuxt BFF (SSR) ──Bearer JWT──▶ Spring Boot API
                          │
                          └──OAuth Code+PKCE──▶ Keycloak ──IdP brokering──▶ Google
```

For deeper rationale (architecture decisions, locked-in tradeoffs, the issuer-pinning trick that makes this work) see [`CLAUDE.md`](./CLAUDE.md) and [`social-login-impl.md`](./social-login-impl.md).

## Prerequisites

- **Docker** with the Compose plugin (`docker compose version` should report v2+)
- **Make** (any modern GNU make)
- **A Google Cloud project** with an OAuth 2.0 Client ID — [walkthrough below](#1-create-a-google-oauth-client)
- For local development without docker (optional): JDK 24, Bun ≥ 1.0

## First-time setup

### 1. Create a Google OAuth Client

You must do this once before the social login can work end-to-end.

1. Go to [Google Cloud Console](https://console.cloud.google.com/) and create (or select) a project.
2. Open **APIs & Services → OAuth consent screen**:
   - User type: **External** (unless your org uses Internal).
   - App name: anything (e.g. `social-login dev`).
   - User support email and developer contact: your email.
   - Save. You can leave Scopes empty — Google grants `openid email profile` by default.
   - Add yourself (and any teammates) as a **Test user**, otherwise Google will block sign-in until the app is published.
3. Open **APIs & Services → Credentials**, click **+ Create Credentials → OAuth client ID**:
   - Application type: **Web application**
   - Name: anything (e.g. `social-login local`)
   - **Authorized redirect URIs** — this is the most common place to make a mistake. Add **exactly one** URI:
     ```
     http://localhost:8080/realms/social-login/broker/google/endpoint
     ```
     This is Keycloak's broker callback, **not** the Nuxt frontend's URL. Keycloak receives Google's authorization code, exchanges it server-to-server, then issues its own code to the BFF.
   - Click **Create**. Copy the **Client ID** and **Client secret**.

### 2. Configure environment variables

```bash
cp .env.example .env
```

Edit `.env` and fill in **at minimum** the five blank values:

| Variable                       | What goes here                                                                           |
|--------------------------------|------------------------------------------------------------------------------------------|
| `GOOGLE_CLIENT_ID`             | The Client ID from step 1                                                                |
| `GOOGLE_CLIENT_SECRET`         | The Client secret from step 1                                                            |
| `FRONTEND_SESSION_SECRET`      | Random string ≥ 48 chars (sealed cookies). Generate with `openssl rand -base64 36`       |
| `FRONTEND_TOKEN_KEY`           | Base64 of **exactly** 32 bytes (AES-256-GCM key). Generate with `openssl rand -base64 32` |
| `KEYCLOAK_REALM_CLIENT_SECRET` | Any random string ≥ 32 chars. Generate with `openssl rand -base64 24`                    |

`FRONTEND_TOKEN_KEY` is *not* the same as `FRONTEND_SESSION_SECRET` — the token key encrypts access tokens at rest with AES-256-GCM, which strictly requires a 32-byte key. Re-using the longer session secret causes login to fail with `Data provided to an operation does not meet requirements` when the BFF tries to encrypt the token after a successful Google sign-in.

The other secrets (`KEYCLOAK_ADMIN_PASSWORD`, `*_DB_PASSWORD`, `PGADMIN_DEFAULT_PASSWORD`) come pre-blank so you can fill them with sensible local values — defaults of `admin` / `keycloak` / `backend` are fine for local development. **Do not use any of these in production.**

The convention is `<SERVICE>_<NAME>` in SCREAMING_SNAKE_CASE, with `<SERVICE>` being one of: `KEYCLOAK_*`, `KEYCLOAK_DB_*`, `KEYCLOAK_REALM_*`, `BACKEND_*`, `BACKEND_DB_*`, `FRONTEND_*`, `PGADMIN_*`, `GOOGLE_*`. `*_HTTP_PORT` is the port a service listens on inside its container, `*_HTTP_HOST_PORT` is the host-mapped port.

### 3. Bring up the stack

```bash
make up
```

First-time launch builds the Keycloak realm-init image, the backend (Spring Boot fat jar), and the frontend (Nuxt + Nitro), and pulls Postgres / Keycloak / PgAdmin images. It takes 1–3 minutes on a warm Docker cache.

When it's done, `make ps` should show every service `running` (and the three with healthchecks marked `healthy`):

```
backend       Up
backend-db    Up (healthy)
frontend      Up
keycloak      Up (healthy)
keycloak-db   Up (healthy)
pgadmin       Up
```

The one-shot `keycloak-realm-init` service exits 0 after creating the realm — that's expected.

### 4. Try it

| URL                          | What you'll see                                       |
|------------------------------|-------------------------------------------------------|
| http://localhost:3000        | Home page with **Login with Google** button          |
| http://localhost:3000/profile| Your name / email / picture (after login)            |
| http://localhost:8080        | Keycloak admin console (sign in with `KEYCLOAK_ADMIN_USER` / `KEYCLOAK_ADMIN_PASSWORD`) |
| http://localhost:8081/actuator/health | Spring Boot health (`{"status":"UP"}`)        |
| http://localhost:5050        | PgAdmin (sign in with `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD`); both DBs are pre-registered |

Click **Login with Google**. You'll go through the standard Google consent screen, land back on the BFF, and `/profile` will render with the data Google sent.

If you set up your `.env` *after* the first `make up` (so the realm-init ran without `GOOGLE_*`), run:

```bash
make realm-reset
```

This drops the realm and re-runs the bootstrap so the Google identity provider gets registered.

## Common commands

Run `make help` for the full list. The ones you'll use most:

```bash
make up           # start everything in the background
make down         # stop everything (volumes preserved)
make restart      # down + up
make logs         # tail all logs
make logs-backend # or logs-frontend, logs-keycloak
make ps           # service status
make clean        # ⚠️  down + remove volumes (destroys all data)
make realm-reset  # drop the Keycloak realm and re-bootstrap

make dev-backend  # run Spring Boot on the host with live reload
make dev-frontend # run Nuxt on the host with HMR
make test-backend # ./gradlew test

make shell-backend
make shell-frontend
make db-keycloak  # psql into the Keycloak DB
make db-backend   # psql into the backend DB
```

## Project structure

```
.
├── backend/                # Spring Boot 4 / Kotlin / JDK 24 — JWT-protected /api/me
├── frontend/               # Nuxt 4 SSR BFF — pages, server routes, nuxt-oidc-auth
├── infra/
│   ├── docker-compose.yml  # all services; reads ../.env
│   ├── keycloak/realm-init # one-shot bootstrap container (kcadm.sh)
│   └── pgadmin             # auto-loaded servers.json + entrypoint shim
├── docs/
│   └── bff-token-validation.md  # known-issue: BFF skips JWT validation (defense-in-depth gap, not a vuln)
├── .env.example            # commit this with secrets blanked
├── .env                    # gitignored; your local values
├── Makefile                # `make help` for targets
├── CLAUDE.md               # high-level guidance for AI coding assistants
└── social-login-impl.md    # binding spec / user stories / locked decisions
```

## Troubleshooting

### "invalid_token" / 401 from `/api/me` even though I just logged in

99% of the time this is the **issuer-mismatch trap**. Spring Boot's resource server validates the `iss` claim of every JWT against `BACKEND_OIDC_ISSUER_URI`. If Keycloak issues tokens with a different `iss` than what the backend expects, validation fails.

`KEYCLOAK_HOSTNAME` (read by Keycloak as `KC_HOSTNAME`) is what gets stamped into the `iss` claim. It **must** match `BACKEND_OIDC_ISSUER_URI` exactly (modulo trailing slashes). Both default to `http://localhost:8080`.

If you change either value (e.g. to use a different host port), you must change both.

### "Login with Google" redirects me, then I get a Google error

- `redirect_uri_mismatch` → the Authorized redirect URI in your Google OAuth Client doesn't exactly match `http://localhost:8080/realms/social-login/broker/google/endpoint`. Trailing slashes, http vs https, port number — Google checks all of it.
- `access_blocked: This app is blocked` or `Error 403` → your Google account isn't on the test-user list of the consent screen. Add it.

### Sessions disappear every time I rebuild the frontend

Your `FRONTEND_SESSION_SECRET` is shorter than 48 characters. The lib silently falls back to a random secret each restart, which invalidates all existing session cookies. Generate a longer one with `openssl rand -base64 36`.

### Login completes at Google but the BFF returns 500 on the callback

`POST /auth/keycloak/callback` returning 500 with the server log saying `Data provided to an operation does not meet requirements` means `FRONTEND_TOKEN_KEY` is not a valid AES-256-GCM key. It must base64-decode to **exactly** 32 bytes. Regenerate with:

```bash
openssl rand -base64 32   # 44-character string, decodes to 32 bytes
```

Don't re-use `FRONTEND_SESSION_SECRET` — that one is intentionally longer and won't satisfy AES's strict length requirement.

### Keycloak fails to start with `password authentication failed for user "keycloak"` (or `"backend"`)

You changed a `*_DB_PASSWORD` in `.env` after the database volume was already created. Postgres only initialises credentials on **first volume creation** — once the volume exists, the in-database password is locked to whatever was set the first time, and the new value in `.env` no longer matches.

```bash
make clean   # ⚠️  wipes both DB volumes
make up
```

`make clean` is destructive. If you have data you care about in either DB, dump it first (e.g. `docker compose exec keycloak-db pg_dump ...`) and restore after.

### Realm-init fails with "could not authenticate after 60 attempts"

Keycloak didn't come up in time. `make logs-keycloak` to see why — usually it's the keycloak-db not being ready yet (despite the healthcheck), or the admin credentials being wrong. Confirm `KEYCLOAK_ADMIN_USER` and `KEYCLOAK_ADMIN_PASSWORD` in `.env` match what you expect, then `make restart`.

### I changed `KEYCLOAK_REALM_*` values in `.env` and they aren't taking effect

The realm-init bootstrap is **idempotent per entity** (realm, client, mappers, IdP), but it doesn't *update* anything that already exists. If you need to change realm-level settings, run `make realm-reset` to drop and re-bootstrap.

## Security posture

- Tokens never reach the browser. The BFF stores access/refresh tokens encrypted in server-side storage and forwards them to the backend over the in-network connection. The browser only ever sees an HttpOnly, SameSite=Lax session cookie.
- The backend independently validates every JWT against Keycloak's JWKS. The BFF currently does not — see [`docs/bff-token-validation.md`](./docs/bff-token-validation.md) for the rationale and the path to closing that defense-in-depth gap.
- The Nuxt OIDC middleware is **fail-closed by default**: every page requires authentication unless explicitly exempted (currently only the home page).
- The values in `.env.example` are placeholders. Generate real secrets for any non-local deployment with `openssl rand -base64 N`.

## Where to read next

- [`CLAUDE.md`](./CLAUDE.md) — locked design decisions and the why behind each.
- [`social-login-impl.md`](./social-login-impl.md) — the binding spec / user stories.
- [`docs/bff-token-validation.md`](./docs/bff-token-validation.md) — known tech debt on the BFF.
