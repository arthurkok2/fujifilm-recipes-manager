#!/usr/bin/env bash
set -euo pipefail

export POSTGRES_HOST="${POSTGRES_HOST:-db}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_WAIT_TIMEOUT="${POSTGRES_WAIT_TIMEOUT:-60}"

deadline=$(( $(date +%s) + POSTGRES_WAIT_TIMEOUT ))

until python - "$POSTGRES_HOST" "$POSTGRES_PORT" <<'PY'
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
do
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
