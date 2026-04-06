#!/usr/bin/env bash
set -euo pipefail

export POSTGRES_HOST="${POSTGRES_HOST:-db}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_WAIT_TIMEOUT="${POSTGRES_WAIT_TIMEOUT:-60}"

elapsed=0
until nc -z -w 1 "$POSTGRES_HOST" "$POSTGRES_PORT"; do
  echo "Waiting for PostgreSQL at ${POSTGRES_HOST}:${POSTGRES_PORT}..."
  if [ "$elapsed" -ge "$POSTGRES_WAIT_TIMEOUT" ]; then
    echo "Timed out waiting for PostgreSQL after ${POSTGRES_WAIT_TIMEOUT}s"
    exit 1
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

if [ "${RUN_MIGRATIONS:-1}" = "1" ]; then
  python manage.py migrate --noinput
fi

exec "$@"
