.PHONY: deploy destroy logs cert-renew reset-secrets help
.DEFAULT_GOAL := help

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

-include .env

DOMAIN    ?=
EMAIL     ?=
USER_ID   ?= 1000
DATA_PATH ?=

_DATA_ROOT = $(if $(strip $(DATA_PATH)),$(DATA_PATH),$(CURDIR)/nextcloud-data)
_DB_PATH   = $(_DATA_ROOT)/db
_HTML_PATH = $(_DATA_ROOT)/html
_NC_DATA   = $(_DATA_ROOT)/data

SYSTEMD_DIR := /etc/systemd/system

help:
	@printf 'Usage: make <target>\n\n'
	@printf 'Targets:\n'
	@printf '  deploy        Full deployment: generate secrets, obtain TLS cert, start all services,\n'
	@printf '                and install the background-job cron timer\n'
	@printf '  destroy       Stop and remove containers; remove cron timer (data is preserved)\n'
	@printf '  logs          Follow logs from all containers\n'
	@printf '  cert-renew    Force an immediate certificate renewal\n'
	@printf '  reset-secrets Regenerate DB passwords (requires wiping the DB volume first)\n\n'
	@printf 'Before first deploy:\n'
	@printf '  cp .env.example .env   # then fill in DOMAIN, EMAIL, DATA_PATH, USER_ID\n'

# ── Main targets ──────────────────────────────────────────────────────────────

deploy: _check-env .secrets nginx.conf.generated _create-dirs _init-cert _gen-env-compose
	docker compose --env-file .env.compose up -d --build
	$(MAKE) -s _setup-cron
	@echo ""
	@echo "Nextcloud is running at https://$(DOMAIN)"
	@echo "Visit the URL above to complete the initial setup if needed."

destroy: _gen-env-compose
	$(MAKE) -s _remove-cron
	docker compose --env-file .env.compose down
	@echo ""
	@echo "All containers stopped. Data at $(_DATA_ROOT) is preserved."
	@echo "Run 'make deploy' to bring the stack back up."

logs: _gen-env-compose
	docker compose --env-file .env.compose logs -f

cert-renew:
	docker exec nextcloud-certbot certbot renew --webroot -w /var/www/certbot --force-renewal

reset-secrets:
	@echo "WARNING: Resetting secrets will break database access until the DB volume is wiped"
	@echo "and docker compose up --build is re-run with the new credentials."
	@read -rp "Type 'yes' to continue: " c && [ "$$c" = "yes" ] || exit 1
	rm -f .secrets
	$(MAKE) .secrets

# ── Secret generation (idempotent: only created once) ─────────────────────────

.secrets:
	@printf 'MYSQL_ROOT_PASSWORD=%s\nMYSQL_PASSWORD=%s\n' \
		"$$(openssl rand -hex 24)" \
		"$$(openssl rand -hex 24)" > .secrets
	@echo "Database secrets written to .secrets (do not commit this file)"

# ── Nginx config generation ───────────────────────────────────────────────────

nginx.conf.generated: nginx.conf .env
	DOMAIN=$(DOMAIN) envsubst '$${DOMAIN}' < nginx.conf > nginx.conf.generated

# ── Internal helpers ──────────────────────────────────────────────────────────

_check-env:
	@test -f .env || { \
		echo "Error: .env not found. Run: cp .env.example .env"; \
		echo "Then fill in DOMAIN, EMAIL, DATA_PATH, and USER_ID."; \
		exit 1; \
	}
	@test -n "$(DOMAIN)" || { echo "Error: DOMAIN is not set in .env"; exit 1; }

_create-dirs:
	@mkdir -p "$(_DB_PATH)" "$(_HTML_PATH)" "$(_NC_DATA)" certbot/conf certbot/www

_gen-env-compose:
	@{ \
		cat .env; \
		[ -f .secrets ] && cat .secrets || true; \
		echo "DB_PATH=$(_DB_PATH)"; \
		echo "HTML_PATH=$(_HTML_PATH)"; \
		echo "NC_DATA_PATH=$(_NC_DATA)"; \
	} > .env.compose

_init-cert:
	@echo "Checking TLS certificate for $(DOMAIN)..."
	@docker rm -f nextcloud-nginx-bootstrap 2>/dev/null || true
	@docker run -d --name nextcloud-nginx-bootstrap \
		-p 80:80 \
		-v "$(CURDIR)/nginx-bootstrap.conf:/etc/nginx/conf.d/default.conf:ro" \
		-v "$(CURDIR)/certbot/www:/var/www/certbot" \
		nginx:stable-alpine
	@docker run --rm \
		-v "$(CURDIR)/certbot/conf:/etc/letsencrypt" \
		-v "$(CURDIR)/certbot/www:/var/www/certbot" \
		certbot/certbot certonly --webroot \
			--keep-until-expiring --non-interactive \
			-w /var/www/certbot \
			-d "$(DOMAIN)" \
			$(if $(strip $(EMAIL)),--email "$(EMAIL)" --no-eff-email,--register-unsafely-without-email) \
			--agree-tos || \
	{ docker rm -f nextcloud-nginx-bootstrap; exit 1; }
	@docker rm -f nextcloud-nginx-bootstrap

_setup-cron:
	@echo "Installing nextcloud background-job cron timer..."
	@sed 's|__USER_ID__|$(USER_ID)|g' systemd/nextcloud-cron.service \
		| sudo tee "$(SYSTEMD_DIR)/nextcloud-cron.service" > /dev/null
	@sudo cp systemd/nextcloud-cron.timer "$(SYSTEMD_DIR)/nextcloud-cron.timer"
	@sudo systemctl daemon-reload
	@sudo systemctl enable --now nextcloud-cron.timer
	@echo "Background-job timer enabled (runs every 5 minutes)."

_remove-cron:
	@if systemctl is-enabled nextcloud-cron.timer &>/dev/null; then \
		echo "Removing nextcloud background-job cron timer..."; \
		sudo systemctl disable --now nextcloud-cron.timer 2>/dev/null || true; \
		sudo rm -f "$(SYSTEMD_DIR)/nextcloud-cron.service" \
		           "$(SYSTEMD_DIR)/nextcloud-cron.timer"; \
		sudo systemctl daemon-reload; \
	fi
