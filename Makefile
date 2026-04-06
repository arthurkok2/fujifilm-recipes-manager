VENV    := .venv
PYTHON  := $(VENV)/bin/python
PIP     := $(VENV)/bin/pip
PYTEST  := $(VENV)/bin/pytest
CELERY  := $(VENV)/bin/celery
DOCKER_COMPOSE := docker compose --env-file .env.docker

.PHONY: setup run worker test help docker-up docker-up-async docker-down docker-logs docker-shell

## setup   — create venv, install deps, configure settings, run migrations
setup: $(VENV)/.deps-installed
	@echo "[setup] Using tracked env-driven Django settings in src/config/settings.py"
	@echo "[setup] Running database migrations..."
	@$(PYTHON) manage.py migrate
	@echo ""
	@echo "Done. Run 'make run' to start the server."

# Re-run pip only when requirements.txt changes (sentinel file tracks this).
$(VENV)/.deps-installed: requirements.txt $(VENV)/bin/activate
	@echo "[setup] Installing Python dependencies..."
	@$(PIP) install --quiet -r requirements.txt
	@touch $@

$(VENV)/bin/activate:
	@echo "[setup] Creating virtual environment..."
	@python3 -m venv $(VENV)

## run     — start the Django development server
run:
	$(PYTHON) manage.py runserver

## worker  — start a Celery worker (requires RabbitMQ)
worker:
	$(CELERY) -A src.config worker --loglevel=info --concurrency=8

## test    — run the test suite
test:
	$(PYTEST)

## docker-up        — start the Docker stack with build
docker-up:
	$(DOCKER_COMPOSE) up --build

## docker-up-async  — start the Docker stack with async services
docker-up-async:
	$(DOCKER_COMPOSE) --profile async up --build

## docker-down      — stop the Docker stack
docker-down:
	$(DOCKER_COMPOSE) down

## docker-logs      — follow web container logs
docker-logs:
	$(DOCKER_COMPOSE) logs -f web

## docker-shell     — open a shell in the web container
docker-shell:
	$(DOCKER_COMPOSE) exec web bash

## help    — list available targets
help:
	@grep -E '^## ' Makefile | sed 's/^## //'
