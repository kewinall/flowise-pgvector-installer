#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
need_root
load_env

failed=0

echo "== Containers =="
dc ps

echo
echo "== Flowise API =="
if dc exec -T flowise curl -fsS http://localhost:3000/api/v1/ping; then
  echo
else
  echo "Flowise API 檢查失敗" >&2
  failed=1
fi

echo
echo "== PostgreSQL =="
if dc exec -T postgres pg_isready -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DEFAULT_DB"; then
  :
else
  failed=1
fi

echo
echo "== Flowise tables =="
dc exec -T postgres psql -U "$POSTGRES_ADMIN_USER" -d "$FLOWISE_DB_NAME" \
  -Atc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"

echo
echo "== pgvector extension =="
if ! dc exec -T postgres psql -U "$POSTGRES_ADMIN_USER" -d "$VECTOR_DB_NAME" \
  -Atc "SELECT extname || ' ' || extversion FROM pg_extension WHERE extname='vector';"; then
  failed=1
fi

exit "$failed"
