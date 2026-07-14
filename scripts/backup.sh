#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
need_root
load_env

stamp="$(date +%Y%m%d-%H%M%S)"
backup_root="${1:-$INSTALL_DIR/backups}"
backup_dir="$backup_root/$stamp"
mkdir -p "$backup_dir"
chmod 700 "$backup_root" "$backup_dir"

flowise_stopped=false
restart_flowise() {
  if [[ "$flowise_stopped" == true ]]; then
    echo "重新啟動 Flowise..."
    dc up -d flowise >/dev/null || true
  fi
}
trap restart_flowise EXIT

echo "停止 Flowise 以建立一致性備份..."
dc stop flowise
flowise_stopped=true

echo "[1/4] 備份 Flowise 應用資料庫..."
dc exec -T postgres pg_dump \
  -U "$POSTGRES_ADMIN_USER" \
  --format=custom --no-owner --no-acl \
  "$FLOWISE_DB_NAME" > "$backup_dir/flowise.dump"

echo "[2/4] 備份 pgvector 資料庫..."
dc exec -T postgres pg_dump \
  -U "$POSTGRES_ADMIN_USER" \
  --format=custom --no-owner --no-acl --no-comments --exclude-extension=vector \
  "$VECTOR_DB_NAME" > "$backup_dir/flowise_vector.dump"

echo "[3/4] 備份 Flowise 檔案與金鑰目錄..."
docker run --rm \
  -v flowise_data:/data:ro \
  -v "$backup_dir:/backup:Z" \
  "pgvector/pgvector:$PGVECTOR_IMAGE_TAG" \
  sh -c 'tar -czf /backup/flowise_data.tar.gz -C /data .'

echo "[4/4] 備份設定與產生校驗碼..."
cp -p "$ENV_FILE" "$backup_dir/.env"
cp -p "$COMPOSE_FILE" "$backup_dir/compose.yaml"
(
  cd "$backup_dir"
  sha256sum flowise.dump flowise_vector.dump flowise_data.tar.gz .env compose.yaml > SHA256SUMS
)
chmod 600 "$backup_dir/.env" "$backup_dir"/*.dump "$backup_dir"/*.tar.gz "$backup_dir/SHA256SUMS"

echo "重新啟動 Flowise..."
dc up -d flowise
flowise_stopped=false
if ! wait_healthy flowise 300; then
  dc logs --tail=200 flowise
  fatal "備份已建立，但 Flowise 重新啟動後未通過健康檢查。"
fi
trap - EXIT

retention="${BACKUP_RETENTION_DAYS:-30}"
if [[ "$retention" =~ ^[0-9]+$ ]] && (( retention > 0 )); then
  find "$backup_root" -mindepth 1 -maxdepth 1 -type d -mtime "+$retention" -print -exec rm -rf {} +
fi

echo "備份完成：$backup_dir"
