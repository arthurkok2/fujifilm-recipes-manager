#!/usr/bin/env bash
set -euo pipefail

export POSTGRES_HOST="${POSTGRES_HOST:-db}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_WAIT_TIMEOUT="${POSTGRES_WAIT_TIMEOUT:-60}"

deadline=$(( $(date +%s) + POSTGRES_WAIT_TIMEOUT ))

until nc -z -w 1 "$POSTGRES_HOST" "$POSTGRES_PORT"; do
  echo "Waiting for PostgreSQL at ${POSTGRES_HOST}:${POSTGRES_PORT}..."
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "Timed out waiting for PostgreSQL after ${POSTGRES_WAIT_TIMEOUT}s"
    exit 1
  fi
done

if [ "${RUN_MIGRATIONS:-1}" = "1" ]; then
  python manage.py migrate --noinput
fi

exec "$@"
