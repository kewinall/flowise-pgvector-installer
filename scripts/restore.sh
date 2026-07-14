#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
need_root
load_env

backup_dir="${1:-}"
[[ -n "$backup_dir" ]] || fatal "用法：flowise-ctl restore /path/to/backup/YYYYMMDD-HHMMSS"
backup_dir="$(cd "$backup_dir" && pwd)"
for file in flowise.dump flowise_vector.dump flowise_data.tar.gz SHA256SUMS; do
  [[ -f "$backup_dir/$file" ]] || fatal "備份缺少檔案：$file"
done

(
  cd "$backup_dir"
  sha256sum -c SHA256SUMS --ignore-missing
)

cat <<EOF
即將以以下備份覆蓋目前資料：
  $backup_dir
此操作會重建兩個資料庫並覆蓋 Flowise 檔案 Volume。
EOF
read -r -p "輸入 RESTORE 才繼續：" answer
[[ "$answer" == "RESTORE" ]] || fatal "已取消。"

echo "停止 Flowise..."
dc stop flowise

echo "重建 Flowise 應用資料庫..."
dc exec -T postgres psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DEFAULT_DB" \
  -v ON_ERROR_STOP=1 \
  -v db="$FLOWISE_DB_NAME" -v db_user="$FLOWISE_DB_USER" <<'EOSQL'
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = :'db' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS :"db";
CREATE DATABASE :"db" OWNER :"db_user" ENCODING 'UTF8';
EOSQL
cat "$backup_dir/flowise.dump" | dc exec -T postgres pg_restore \
  -U "$FLOWISE_DB_USER" -d "$FLOWISE_DB_NAME" --no-owner --no-acl --exit-on-error

echo "重建 pgvector 資料庫..."
dc exec -T postgres psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DEFAULT_DB" \
  -v ON_ERROR_STOP=1 \
  -v db="$VECTOR_DB_NAME" -v db_user="$VECTOR_DB_USER" <<'EOSQL'
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = :'db' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS :"db";
CREATE DATABASE :"db" OWNER :"db_user" ENCODING 'UTF8';
EOSQL

dc exec -T postgres psql -U "$POSTGRES_ADMIN_USER" -d "$VECTOR_DB_NAME" \
  -v ON_ERROR_STOP=1 -v db_user="$VECTOR_DB_USER" <<'EOSQL'
CREATE EXTENSION IF NOT EXISTS vector;
GRANT USAGE, CREATE ON SCHEMA public TO :"db_user";
EOSQL

cat "$backup_dir/flowise_vector.dump" | dc exec -T postgres pg_restore \
  -U "$VECTOR_DB_USER" -d "$VECTOR_DB_NAME" --no-owner --no-acl --exit-on-error

echo "還原 Flowise 檔案 Volume..."
docker run --rm \
  -v flowise_data:/data \
  -v "$backup_dir:/backup:ro,Z" \
  "pgvector/pgvector:$PGVECTOR_IMAGE_TAG" \
  sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -xzf /backup/flowise_data.tar.gz -C /data'

# 保留目前主機的 DB 密碼、URL、Port 與版本，只還原 Flowise 應用層的加密/驗證金鑰。
# 這可讓備份移轉到新主機時，既有 Credential 仍能解密。
if [[ -f "$backup_dir/.env" ]]; then
  echo "合併備份中的 Flowise 加密與驗證金鑰..."
  for key in \
    FLOWISE_SECRETKEY_OVERWRITE \
    JWT_AUTH_TOKEN_SECRET \
    JWT_REFRESH_TOKEN_SECRET \
    EXPRESS_SESSION_SECRET \
    TOKEN_HASH_SECRET; do
    value="$(grep -m1 "^${key}=" "$backup_dir/.env" | cut -d= -f2- || true)"
    if [[ -n "$value" ]]; then
      if grep -q "^${key}=" "$ENV_FILE"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
      else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
      fi
    fi
  done
  chmod 600 "$ENV_FILE"
fi

echo "重新啟動服務..."
dc up -d
if ! wait_healthy flowise 300; then
  dc logs --tail=200 flowise
  fatal "Flowise 未通過健康檢查。"
fi

echo "還原完成。"
