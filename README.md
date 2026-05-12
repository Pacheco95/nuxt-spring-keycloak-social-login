# Social Login (Keycloak-brokered Google OAuth)

[![CI](https://github.com/Pacheco95/nuxt-spring-keycloak-social-login/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Pacheco95/nuxt-spring-keycloak-social-login/actions/workflows/ci.yml)
[![Kotlin](https://img.shields.io/badge/Kotlin-2.2-7F52FF?logo=kotlin&logoColor=white)](https://kotlinlang.org)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-4.0-6DB33F?logo=springboot&logoColor=white)](https://spring.io/projects/spring-boot)
[![Nuxt](https://img.shields.io/badge/Nuxt-4-00DC82?logo=nuxt&logoColor=white)](https://nuxt.com)
[![Keycloak](https://img.shields.io/badge/Keycloak-26-4D4D4D?logo=keycloak&logoColor=white)](https://www.keycloak.org)

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
- For host-side dev (running backend/frontend live, not in compose): JDK 24 + Bun ≥ 1.0, **or** the [dev container](#using-the-dev-container) (no host install needed)

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

## Using the dev container

If you'd rather not install JDK 24 and Bun on your host, the repo ships a [Dev Container](https://containers.dev/) under `.devcontainer/`. It provides a Debian-based workspace with Temurin 24 (via SDKMAN), Bun, and the Docker CLI, joined to the same `social-login` docker network that the infra stack uses. The workspace publishes host `:3000` and `:8081` directly, so your browser hits the dev servers without any VS Code tunneling in the path.

You still need Docker and Make on the host. Everything else lives in the container.

**Open it:**

- **VS Code / Cursor** — install the *Dev Containers* extension, then run `Dev Containers: Reopen in Container` from the command palette (`Cmd/Ctrl+Shift+P`).
- **CLI** — `devcontainer up --workspace-folder .` (requires the [`@devcontainers/cli`](https://github.com/devcontainers/cli) npm package).

The first launch installs the JDK and Bun features and takes ~2 minutes. Subsequent opens are seconds.

### Workflow inside the devcontainer

The devcontainer flow is **different from the host flow**. Instead of `make up` (which runs *every* service in compose, including production builds of the frontend and backend), you run only the supporting infra in compose and the two apps as live-reload dev servers inside the workspace:

```bash
make up-infra      # DBs, Keycloak, realm-init, pgadmin — leave running
make dev-backend   # in one terminal — ./gradlew bootRun
make dev-frontend  # in another terminal — nuxt dev (HMR)
```

`make dev-backend` / `make dev-frontend` re-create the same env mapping the compose `backend` / `frontend` services receive (Spring datasource, JWKS URI, `NUXT_OIDC_*`, etc.), sourced from `.env` and rewritten for in-workspace addressing. **Run them through `make`** — raw `./gradlew bootRun` or `bun run dev` will fail (Spring with `Connection to localhost:5432 refused`, Nuxt with `No ... secret set, using a random secret` warnings and a broken OAuth flow).

The "Try it" URLs from [step 4](#4-try-it) work unchanged — `localhost:3000`, `:8080`, `:8081`, `:5050`.

The workspace's docker-network membership means you can also reach the infra containers by service name from a workspace terminal:

```bash
curl http://keycloak:8080/health/ready    # the keycloak container
psql -h backend-db -U backend …           # the backend Postgres
```

Stopping the dev container does not stop the infra stack (and vice versa) — they're independent compose lifecycles that just happen to share a network. `make clean` still wipes everything.

### Don't run `make up` while the devcontainer is up

The workspace publishes host `:3000` and `:8081` for the dev servers, which collides with the compose `frontend` / `backend` services. `make up` will fail to start those two while the devcontainer is running. The two workflows are mutually exclusive:

- **Devcontainer**: `make up-infra` + `make dev-backend` + `make dev-frontend`.
- **Host**: `make up` (no devcontainer running).

### Compose-mode caveat

The dev container's compose file (`.devcontainer/docker-compose.yml`) is intentionally standalone — it does *not* `include` `infra/docker-compose.yml`. Pulling infra in would force `${VAR}` interpolation on every service and require a `.env` symlinked into `infra/`. Sharing the network via matching project names (`name: social-login` in both files) gets us the same outcome with no env-file gymnastics.

## Common commands

Run `make help` for the full list. The ones you'll use most:

```bash
make up           # start everything in the background (host flow)
make up-infra     # start only DBs / Keycloak / pgadmin (devcontainer flow)
make down         # stop everything (volumes preserved)
make restart      # down + up
make logs         # tail all logs
make logs-backend # or logs-frontend, logs-keycloak
make ps           # service status
make clean        # ⚠️  down + remove volumes (destroys all data)
make realm-reset  # drop the Keycloak realm and re-bootstrap

make dev-backend  # run Spring Boot with live reload (workspace or host)
make dev-frontend # run Nuxt with HMR (workspace or host)
make test-backend # ./gradlew test

make shell-backend
make shell-frontend
make db-keycloak  # psql into the Keycloak DB
make db-backend   # psql into the backend DB
```

## Running tests

Two tiers — full details in [`docs/testing.md`](./docs/testing.md):

```bash
make test-stack   # Tier 1: ~30s HTTP/JWT smoke (no browser)
make test-e2e     # Tier 2: Playwright browser-driven journey with a mock Google
make test         # Both
make test-clean   # Tear down the test stack and remove e2e/playwright-report, e2e/test-results
```

Tier 2 swaps Google for a local mock OIDC server inside the docker network, so the entire login → profile → logout journey runs hermetically — no Google account needed, no internet required, fully deterministic.

### How to run them properly

Both tiers hit `http://localhost:…` directly (Keycloak `:8080`, backend `:8081`, BFF `:3000`, pgadmin `:5050`). That has three consequences:

1. **Run from the host shell, not the devcontainer.** Inside the devcontainer, `localhost` is the workspace's own loopback and does not reach the host-published compose ports.
2. **Bring the full stack up first with `make up`, not `make up-infra`.** Tier 1 expects the compose `frontend` and `backend` services to be running; `make up-infra` doesn't start them. Tier 2 then layers the test override (mock-google + IdP swap) on top of an already-running stack.
3. **Stop the devcontainer first if it's running.** It publishes `:3000` / `:8081` for the dev servers and will collide with the compose `frontend` / `backend` services. From the host: `docker stop social-login-workspace-1`.

The happy path:

```bash
# from the host shell, devcontainer stopped
make up
make test
make test-clean   # before next test run, or before going back to make up
```

> ⚠️ `make test-clean` (and `make test-e2e-down`) issue `docker compose down` across both `docker-compose.yml` *and* `docker-compose.test.yml`, which tears down the **whole** stack — not just the test-only services. Run `make up` again afterwards.

If you only want the backend unit tests (no stack required), use `make test-backend` — that runs `./gradlew test` and works from anywhere with a JDK 24.

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
│   ├── bff-token-validation.md  # known-issue: BFF skips JWT validation (defense-in-depth gap, not a vuln)
│   └── testing.md               # the two test tiers and the mock-IdP design
├── e2e/                    # Playwright e2e suite (browser-driven)
├── scripts/
│   └── test-stack.sh       # bash smoke (~30s, no browser)
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

### `Connection to localhost:5432 refused` running the backend in the devcontainer

You ran `./gradlew bootRun` directly. The compose env mapping (datasource URL, JWKS URI, etc.) is re-created by `make dev-backend` from `.env`; raw `bootRun` falls back to Spring defaults (`localhost:5432`), which inside the devcontainer doesn't reach `backend-db`. Use `make dev-backend`.

### `[GET] http://localhost:8081/api/me: <no response>` from the BFF

The BFF reaches the backend at `localhost:8081` (where `make dev-backend` listens) and nothing is answering there. Either `make dev-backend` isn't running, or you tried `make up` (the compose `backend` can't bind `:8081` while the devcontainer holds it). Start `make dev-backend` in a separate terminal.

### "site can't be reached" on `/auth/keycloak/callback` in the devcontainer

The workspace must publish `:3000` directly to the host (defined in `.devcontainer/docker-compose.yml`). If you opened the devcontainer before that change landed, **rebuild** it: VS Code → *Dev Containers: Rebuild Container*. A simple reopen does not re-read the compose file.

### "Login with Google" redirects to `localhost:9000` and the page can't be reached

You ran `make test-e2e` (or `make test-e2e-up`) before. That target's `keycloak-test-config` step **rewrites** the realm's `google` IdP to point at the in-network `mock-google` service on `localhost:9000` — see `infra/keycloak/test-config/configure-mock-idp.sh`. The swap is persisted in the `keycloak-db-data` volume, so it survives `make test-e2e-down` and `make down`.

When you then bring the production stack back up with `make up`, `mock-google` is gone but the realm still has `authorizationUrl=http://localhost:9000/authorize`, so clicking Login redirects the browser to a port nothing is listening on.

Fix: re-run the production bootstrap.

```bash
make realm-reset    # drops the realm and re-creates the real Google IdP from .env
```

If you want a clean slate (also wipes both DB volumes):

```bash
make clean && make up
```

## Security posture

- Tokens never reach the browser. The BFF stores access/refresh tokens encrypted in server-side storage and forwards them to the backend over the in-network connection. The browser only ever sees an HttpOnly, SameSite=Lax session cookie.
- The backend independently validates every JWT against Keycloak's JWKS. The BFF currently does not — see [`docs/bff-token-validation.md`](./docs/bff-token-validation.md) for the rationale and the path to closing that defense-in-depth gap.
- The Nuxt OIDC middleware is **fail-closed by default**: every page requires authentication unless explicitly exempted (currently only the home page).
- The values in `.env.example` are placeholders. Generate real secrets for any non-local deployment with `openssl rand -base64 N`.

## Where to read next

- [`CLAUDE.md`](./CLAUDE.md) — locked design decisions and the why behind each.
- [`social-login-impl.md`](./social-login-impl.md) — the binding spec / user stories.
- [`docs/bff-token-validation.md`](./docs/bff-token-validation.md) — known tech debt on the BFF.
