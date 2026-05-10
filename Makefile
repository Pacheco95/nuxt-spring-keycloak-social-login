# Common dev workflows. All compose commands point at infra/docker-compose.yml
# and the project-root .env so you can run `make <target>` from anywhere in
# the repo (Make resolves to the directory of this Makefile).
#
# Run `make help` for the list of targets.

ROOT := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
COMPOSE := docker compose -f $(ROOT)infra/docker-compose.yml --env-file $(ROOT).env
COMPOSE_TEST := docker compose -f $(ROOT)infra/docker-compose.yml -f $(ROOT)infra/docker-compose.test.yml --env-file $(ROOT).env

# Pull .env values into Make's environment so recipes can use $$VAR. The guard
# avoids breaking targets like `help` on a fresh checkout where .env is missing.
ifneq (,$(wildcard $(ROOT).env))
include $(ROOT).env
export
endif

.DEFAULT_GOAL := help

.PHONY: help up up-infra up-build down restart ps logs logs-backend logs-frontend logs-keycloak \
        build clean realm-reset test test-backend test-stack test-e2e test-e2e-up test-e2e-down \
        dev-backend dev-frontend shell-backend shell-frontend db-keycloak db-backend

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*?## "; printf "Usage: make <target>\n\nTargets:\n"} \
	     /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
	     $(MAKEFILE_LIST)

# ── Lifecycle ─────────────────────────────────────────────────────────────
up: ## Start the full stack in the background
	$(COMPOSE) up -d

up-infra: ## Start only infra (DBs, Keycloak, realm-init, pgadmin) — pair with make dev-backend / dev-frontend
	$(COMPOSE) up -d keycloak-db backend-db keycloak keycloak-realm-init pgadmin

up-build: ## Rebuild local images and start the stack
	$(COMPOSE) up -d --build

down: ## Stop and remove containers (volumes preserved)
	$(COMPOSE) down

restart: down up ## Stop and start the full stack

ps: ## Show service status
	$(COMPOSE) ps

logs: ## Tail logs for all services (Ctrl-C to stop)
	$(COMPOSE) logs -f --tail=100

logs-backend: ## Tail backend logs
	$(COMPOSE) logs -f --tail=200 backend

logs-frontend: ## Tail frontend logs
	$(COMPOSE) logs -f --tail=200 frontend

logs-keycloak: ## Tail Keycloak logs
	$(COMPOSE) logs -f --tail=200 keycloak

build: ## Rebuild backend, frontend, and realm-init images
	$(COMPOSE) build backend frontend keycloak-realm-init

clean: ## Stop containers AND remove volumes (destroys all data)
	$(COMPOSE) down -v

# ── Realm management ──────────────────────────────────────────────────────
realm-reset: ## Drop the realm and re-run bootstrap (use after editing .env Google credentials)
	@echo "Dropping realm '$(KEYCLOAK_REALM_NAME)' ..."
	@$(COMPOSE) exec -T keycloak /opt/keycloak/bin/kcadm.sh config credentials \
		--server http://localhost:$(KEYCLOAK_HTTP_PORT) --realm master \
		--user "$(KEYCLOAK_ADMIN_USER)" --password "$(KEYCLOAK_ADMIN_PASSWORD)" >/dev/null
	@$(COMPOSE) exec -T keycloak /opt/keycloak/bin/kcadm.sh delete \
		"realms/$(KEYCLOAK_REALM_NAME)" 2>/dev/null \
		|| echo "  (realm did not exist — continuing)"
	$(COMPOSE) run --rm keycloak-realm-init

# ── Local-host development (no docker) ────────────────────────────────────
dev-backend: ## Run the backend on the host with gradle bootRun (live reload)
	@# Spring's datasource/JWKS config only exists as a mapping inside the
	@# `backend` block of infra/docker-compose.yml. Running bootRun directly
	@# bypasses that, so re-create the same mapping here from .env.
	@#
	@# Host vs devcontainer: same idea as dev-frontend — host reaches the DBs
	@# / Keycloak on their published localhost ports, devcontainer reaches
	@# them by service name on their in-network ports. JWT issuer URI stays
	@# pinned to KEYCLOAK_HOSTNAME (browser-facing) in both modes — Keycloak
	@# issues that value regardless of backchannel path.
	@if [ -f /.dockerenv ]; then \
		DB_HOST=backend-db; DB_PORT=$(BACKEND_DB_PORT); \
		KC_HOST=keycloak;   KC_PORT=$(KEYCLOAK_HTTP_PORT); \
	else \
		DB_HOST=localhost;  DB_PORT=$(BACKEND_DB_HOST_PORT); \
		KC_HOST=localhost;  KC_PORT=$(KEYCLOAK_HTTP_HOST_PORT); \
	fi; \
	cd $(ROOT)backend && \
	SERVER_PORT="$(BACKEND_HTTP_PORT)" \
	SPRING_DATASOURCE_URL="jdbc:postgresql://$$DB_HOST:$$DB_PORT/$(BACKEND_DB_NAME)" \
	SPRING_DATASOURCE_USERNAME="$(BACKEND_DB_USER)" \
	SPRING_DATASOURCE_PASSWORD="$(BACKEND_DB_PASSWORD)" \
	SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI="$(BACKEND_OIDC_ISSUER_URI)" \
	SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWK_SET_URI="http://$$KC_HOST:$$KC_PORT/realms/$(KEYCLOAK_REALM_NAME)/protocol/openid-connect/certs" \
	LOGGING_LEVEL_ROOT="$(BACKEND_LOG_LEVEL)" \
	./gradlew --no-daemon bootRun

dev-frontend: ## Run the frontend on the host with bun (live reload)
	@# The NUXT_OIDC_* env vars only exist as a mapping inside the `frontend`
	@# block of infra/docker-compose.yml. Running `bun run dev` directly
	@# bypasses that, so we re-create the same mapping here from the
	@# FRONTEND_*/KEYCLOAK_* source-of-truth values in .env.
	@#
	@# Host vs devcontainer: from the host we reach Keycloak/backend on their
	@# published localhost ports; from inside the social-login compose network
	@# (devcontainer) we reach them by service name on their in-network ports.
	@# Keycloak's `iss` is pinned to KEYCLOAK_HOSTNAME either way, so a
	@# service-name backchannel does not break issuer validation.
	@# Backend host is always `localhost` because `make dev-backend` runs
	@# bootRun in the same place as `make dev-frontend` (devcontainer
	@# workspace, or the host). Don't use the compose service name even in
	@# devcontainer mode — the `backend` container only exists under
	@# `make up`, not under the dev-server workflow (`make up-infra`).
	@if [ -f /.dockerenv ]; then \
		KC_HOST=keycloak; KC_PORT=$(KEYCLOAK_HTTP_PORT); \
	else \
		KC_HOST=localhost; KC_PORT=$(KEYCLOAK_HTTP_HOST_PORT); \
	fi; \
	BE_HOST=localhost; BE_PORT=$(BACKEND_HTTP_PORT); \
	cd $(ROOT)frontend && \
	NUXT_OIDC_SESSION_SECRET="$(FRONTEND_SESSION_SECRET)" \
	NUXT_OIDC_AUTH_SESSION_SECRET="$(FRONTEND_SESSION_SECRET)" \
	NUXT_OIDC_TOKEN_KEY="$(FRONTEND_TOKEN_KEY)" \
	NUXT_OIDC_PROVIDERS_KEYCLOAK_CLIENT_ID="$(KEYCLOAK_REALM_CLIENT_ID)" \
	NUXT_OIDC_PROVIDERS_KEYCLOAK_CLIENT_SECRET="$(KEYCLOAK_REALM_CLIENT_SECRET)" \
	NUXT_OIDC_PROVIDERS_KEYCLOAK_REDIRECT_URI="$(FRONTEND_OIDC_REDIRECT_URI)" \
	NUXT_OIDC_PROVIDERS_KEYCLOAK_LOGOUT_REDIRECT_URI="$(FRONTEND_OIDC_POST_LOGOUT_REDIRECT_URI)" \
	NUXT_OIDC_PROVIDERS_KEYCLOAK_CALLBACK_REDIRECT_URL=/profile \
	NUXT_OIDC_PROVIDERS_KEYCLOAK_AUTHORIZATION_URL="$(FRONTEND_OIDC_KEYCLOAK_PUBLIC_URL)/realms/$(KEYCLOAK_REALM_NAME)/protocol/openid-connect/auth?kc_idp_hint=google" \
	NUXT_OIDC_PROVIDERS_KEYCLOAK_LOGOUT_URL="$(FRONTEND_OIDC_KEYCLOAK_PUBLIC_URL)/realms/$(KEYCLOAK_REALM_NAME)/protocol/openid-connect/logout" \
	NUXT_OIDC_PROVIDERS_KEYCLOAK_TOKEN_URL="http://$$KC_HOST:$$KC_PORT/realms/$(KEYCLOAK_REALM_NAME)/protocol/openid-connect/token" \
	NUXT_OIDC_PROVIDERS_KEYCLOAK_USER_INFO_URL="http://$$KC_HOST:$$KC_PORT/realms/$(KEYCLOAK_REALM_NAME)/protocol/openid-connect/userinfo" \
	NUXT_BACKEND_INTERNAL_URL="http://$$BE_HOST:$$BE_PORT" \
	bun run dev

test-backend: ## Run backend test suite on the host
	cd $(ROOT)backend && ./gradlew --no-daemon test

# ── Stack & e2e tests ─────────────────────────────────────────────────────
test: test-stack test-e2e ## Run both tiers (stack smoke + e2e)

test-stack: ## Tier 1: HTTP/JWT smoke against the running stack (~30s)
	@bash $(ROOT)scripts/test-stack.sh

test-e2e: test-e2e-up ## Tier 2: Playwright e2e against stack with mocked Google
	cd $(ROOT)e2e && bun install --frozen-lockfile 2>/dev/null || (cd $(ROOT)e2e && bun install)
	cd $(ROOT)e2e && bunx playwright install chromium
	cd $(ROOT)e2e && bunx playwright test

test-e2e-up: ## Bring up the stack with the test override + mock Google
	$(COMPOSE_TEST) up -d --wait

test-e2e-down: ## Tear down the test stack (drops mock-google and the IdP swap)
	$(COMPOSE_TEST) down

# ── Shells ────────────────────────────────────────────────────────────────
shell-backend: ## Open a shell in the running backend container
	$(COMPOSE) exec backend /bin/sh

shell-frontend: ## Open a shell in the running frontend container
	$(COMPOSE) exec frontend /bin/sh

db-keycloak: ## Open psql against the Keycloak database
	$(COMPOSE) exec keycloak-db psql -U "$(KEYCLOAK_DB_USER)" "$(KEYCLOAK_DB_NAME)"

db-backend: ## Open psql against the backend database
	$(COMPOSE) exec backend-db psql -U "$(BACKEND_DB_USER)" "$(BACKEND_DB_NAME)"
