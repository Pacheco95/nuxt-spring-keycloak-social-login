# Common dev workflows. All compose commands point at infra/docker-compose.yml
# and the project-root .env so you can run `make <target>` from anywhere in
# the repo (Make resolves to the directory of this Makefile).
#
# Run `make help` for the list of targets.

ROOT := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
COMPOSE := docker compose -f $(ROOT)infra/docker-compose.yml --env-file $(ROOT).env

# Pull .env values into Make's environment so recipes can use $$VAR. The guard
# avoids breaking targets like `help` on a fresh checkout where .env is missing.
ifneq (,$(wildcard $(ROOT).env))
include $(ROOT).env
export
endif

.DEFAULT_GOAL := help

.PHONY: help up up-build down restart ps logs logs-backend logs-frontend logs-keycloak \
        build clean realm-reset test-backend dev-backend dev-frontend \
        shell-backend shell-frontend db-keycloak db-backend

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*?## "; printf "Usage: make <target>\n\nTargets:\n"} \
	     /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
	     $(MAKEFILE_LIST)

# ── Lifecycle ─────────────────────────────────────────────────────────────
up: ## Start the full stack in the background
	$(COMPOSE) up -d

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
	cd $(ROOT)backend && ./gradlew --no-daemon bootRun

dev-frontend: ## Run the frontend on the host with bun (live reload)
	cd $(ROOT)frontend && bun run dev

test-backend: ## Run backend test suite on the host
	cd $(ROOT)backend && ./gradlew --no-daemon test

# ── Shells ────────────────────────────────────────────────────────────────
shell-backend: ## Open a shell in the running backend container
	$(COMPOSE) exec backend /bin/sh

shell-frontend: ## Open a shell in the running frontend container
	$(COMPOSE) exec frontend /bin/sh

db-keycloak: ## Open psql against the Keycloak database
	$(COMPOSE) exec keycloak-db psql -U "$(KEYCLOAK_DB_USER)" "$(KEYCLOAK_DB_NAME)"

db-backend: ## Open psql against the backend database
	$(COMPOSE) exec backend-db psql -U "$(BACKEND_DB_USER)" "$(BACKEND_DB_NAME)"
