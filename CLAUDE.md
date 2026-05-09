# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project context

Greenfield monorepo whose goal is to implement Google social login using **Keycloak 26 as an identity broker** in front of a Spring Boot API and a Nuxt 4 SSR frontend. The frontend acts as a **BFF**: tokens never reach the browser, only an HttpOnly session cookie does.

The authoritative spec — flow diagrams, user stories, and binding implementation requirements — lives in `social-login-impl.md`. **Read it before making non-trivial changes**; several constraints there are not derivable from the code (it is currently mostly empty scaffolding).

## Architecture (target state)

```
browser ──cookie──▶ Nuxt BFF (SSR) ──Bearer JWT──▶ Spring Boot API
                          │
                          └──OAuth Code+PKCE──▶ Keycloak ──IdP brokering──▶ Google
```

- **Nuxt SSR is the only OAuth client.** It performs the Authorization Code + PKCE exchange server-to-server with Keycloak, stores tokens in a server-side session, and hands the browser an `HttpOnly; Secure; SameSite=Lax` cookie. Expect `nuxt-oidc-auth` to be the integration point.
- **Spring Boot validates JWTs locally** using Keycloak's JWKS (cached). It never talks to Google and never participates in the login redirect dance.
- **Keycloak brokers Google** (and any future IdP). Adding GitHub/Microsoft/password should be a Keycloak realm config change, not a code change — keep the application code provider-agnostic.
- **Two separate Postgres 16 databases**: one for Keycloak, one for the backend. Do not collapse them.
- **Keycloak realm must be auto-configured on first `docker compose up`** (e.g. via Keycloak Admin CLI in an init container). Do not require manual realm setup.

## Repository layout

- `backend/` — Kotlin 2.2 / Spring Boot 4.0 / JDK 24 Gradle project (`com.example.backend`). Currently just the empty `BackendApplication`. Pre-installed starters: `data-jpa`, `flyway`, `security`, `webmvc`, `springdoc-openapi`, plus `jackson-module-kotlin`. `kotlin-jpa` + `allOpen` are configured for `@Entity`/`@MappedSuperclass`/`@Embeddable`.
- `frontend/` — Nuxt 4.4 SSR project. Minimalistic by design — uses **Bun** (`bun.lock`). No auth library installed yet; install what you need.
- `infra/` — **does not yet exist.** All Docker Compose, Keycloak realm bootstrap, PgAdmin server config, and related infra files belong here. Treat this as a hard rule.
- `.env` / `.env.example` — **does not yet exist** but is required at the repo root. The `.env` file is the **single source of truth** for configuration consumed by *every* docker-compose service (backend, frontend BFF, Keycloak, both Postgres instances, PgAdmin). Commit `.env.example` with secrets stripped.
- `Makefile` — does not yet exist; add common dev commands here as you build them out.

## Common commands

Backend (run from `backend/`):
```bash
./gradlew bootRun           # run the API
./gradlew build             # compile + test + jar
./gradlew test              # all tests
./gradlew test --tests "com.example.backend.SomeTest.someMethod"  # single test
```

Frontend (run from `frontend/`, package manager is **Bun**):
```bash
bun install
bun run dev                 # http://localhost:3000
bun run build
bun run preview
```

## Design decisions (locked with the user)

These were confirmed before implementation began — do not silently revisit them. If a constraint forces a change, surface it explicitly.

- **Backend role in v1**: Spring Boot exposes a JWT-protected `GET /api/me` returning `name`, `email`, and `picture` derived from the Keycloak access-token claims. The BFF calls this endpoint to render `/profile`. This deliberately exercises the full Keycloak → Spring JWKS validation chain end-to-end — do *not* render the profile purely from the BFF session.
- **Logout is RP-initiated**: the Log Out button clears the BFF session cookie *and* redirects through Keycloak's `end_session_endpoint` (with `id_token_hint` and `post_logout_redirect_uri`) so the Keycloak SSO session is terminated. Local-only logout is not acceptable — it would let the next "Login with Google" silently re-auth the same user.
- **Google OAuth credentials are user-supplied**: assume the developer has not created a Google Cloud OAuth client yet. The README must contain a step-by-step Google Cloud Console walkthrough (create project → OAuth consent screen → OAuth 2.0 Client ID → exact authorized redirect URI to register, which is Keycloak's broker callback). `.env.example` ships with `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` blank.
- **Local-dev hostnames are pure `localhost:port`**: Keycloak on `:8080`, Nuxt on `:3000`, Spring on `:8081` (or whatever ports are chosen, but all on `localhost`). Inside the docker network the BFF reaches Keycloak via the compose service name (e.g. `keycloak:8080`) for the server-to-server token exchange, **but Keycloak's issuer / `KC_HOSTNAME` must be pinned to `http://localhost:8080`** so the `iss` claim matches what the browser sees during the redirect. Use Keycloak 26's hostname-v2 options (`KC_HOSTNAME`, `KC_HOSTNAME_BACKCHANNEL_DYNAMIC=true`, etc.) — this is the most common source of "issuer mismatch" / "invalid_token" bugs in this setup, so the config and a short comment explaining it should live next to each other.

## Conventions and rules to respect

- **No hard-coded config.** Every URL, port, secret, client ID, realm name, DB credential, etc. must be sourced from `.env`. If you find yourself about to inline `localhost:8080` or a realm name, stop and add an env var instead.
- **Suggest a naming convention for env vars before introducing many of them** (the spec asks for this explicitly). Prefix by service is the typical pattern (e.g. `KC_*`, `BACKEND_DB_*`, `KEYCLOAK_DB_*`, `NUXT_*`).
- **Date-sensitive research**: today is 2026-05-09. When pulling docs/snippets from the web for Nuxt 4, Spring Boot 4, or Keycloak 26, prefer sources from late 2025 onward — these stacks all had breaking changes recently.
