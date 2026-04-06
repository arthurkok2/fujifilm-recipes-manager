#!/usr/bin/env bash
set -euo pipefail

export POSTGRES_HOST="${POSTGRES_HOST:-db}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_WAIT_TIMEOUT="${POSTGRES_WAIT_TIMEOUT:-60}"

deadline=$(( $(date +%s) + POSTGRES_WAIT_TIMEOUT ))
backoff=1
last_error=""

probe_postgres() {
  python - "$POSTGRES_HOST" "$POSTGRES_PORT" <<'PY'
import os
import sys

import psycopg2

host = sys.argv[1]
port = sys.argv[2]

try:
    conn = psycopg2.connect(
        host=host,
        port=port,
        dbname=os.environ.get("POSTGRES_DB", "fujifilm_recipes"),
        user=os.environ.get("POSTGRES_USER", "fujifilm_recipes"),
        password=os.environ.get("POSTGRES_PASSWORD", "fujifilm_recipes"),
        connect_timeout=1,
    )
except Exception:
    raise SystemExit(1)

conn.close()
PY
}

while ! last_error="$(probe_postgres 2>&1)"; do
  echo "Waiting for PostgreSQL at ${POSTGRES_HOST}:${POSTGRES_PORT}..."
  if [ -n "$last_error" ]; then
    printf '%s\n' "$last_error"
  fi

  now="$(date +%s)"
  if [ "$now" -ge "$deadline" ]; then
    echo "Timed out waiting for PostgreSQL after ${POSTGRES_WAIT_TIMEOUT}s"
    if [ -n "$last_error" ]; then
      echo "Last PostgreSQL probe error:"
      printf '%s\n' "$last_error"
    fi
    exit 1
  fi

  remaining=$((deadline - now))
  sleep_for=$backoff
  if [ "$sleep_for" -gt "$remaining" ]; then
    sleep_for="$remaining"
  fi
  sleep "$sleep_for"
  if [ "$backoff" -lt 5 ]; then
    backoff=$((backoff * 2))
  fi
done

if [ "${RUN_MIGRATIONS:-1}" = "1" ]; then
  python manage.py migrate --noinput
fi

exec "$@"
