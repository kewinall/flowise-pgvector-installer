#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
need_root
load_env

YES=false
PURGE_BACKUPS=false
REMOVE_IMAGES=false
NEW_FLOWISE_VERSION="${FLOWISE_VERSION:-3.1.3}"
NEW_PGVECTOR_IMAGE_TAG="${PGVECTOR_IMAGE_TAG:-0.8.4-pg17-bookworm}"
NEW_TZ="${TZ:-Asia/Taipei}"
NEW_FLOWISE_PORT="${FLOWISE_PORT:-3000}"
NEW_FLOWISE_BIND_ADDRESS="${FLOWISE_BIND_ADDRESS:-0.0.0.0}"
NEW_APP_URL="${APP_URL:-}"

usage() {
  cat <<'EOF_USAGE'
用法：sudo flowise-ctl reset-rebuild [選項]

測試環境用的破壞性重建指令。會刪除目前 Flowise/PostgreSQL 容器、資料 Volume 與 .env，
重新產生所有資料庫密碼、JWT、Session、Flowise Credential 加密金鑰，並啟動一個全新的空白環境。

選項：
  --yes                         不要求互動確認
  --purge-backups               同時刪除 /opt/flowise-pgvector/backups 內的備份
  --remove-images               同時刪除目前版本的 Flowise 與 pgvector image，之後重新 pull
  --port PORT                   重建後 Flowise 對外連接埠，預設沿用目前 .env
  --bind-address IP             重建後綁定位置，預設沿用目前 .env
  --app-url URL                 重建後 Flowise 對外網址，預設沿用目前 .env
  --flowise-version VERSION     重建後 Flowise image tag，預設沿用目前 .env
  --pgvector-tag TAG            重建後 pgvector image tag，預設沿用目前 .env
  --timezone TZ                 重建後時區，預設沿用目前 .env
  -h, --help                    顯示說明

範例：
  sudo flowise-ctl reset-rebuild
  sudo flowise-ctl reset-rebuild --yes --purge-backups
  sudo flowise-ctl reset-rebuild --yes --port 3100
EOF_USAGE
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 ))
}

while (( $# > 0 )); do
  case "$1" in
    --yes) YES=true; shift ;;
    --purge-backups) PURGE_BACKUPS=true; shift ;;
    --remove-images) REMOVE_IMAGES=true; shift ;;
    --port) [[ $# -ge 2 ]] || fatal "$1 缺少值"; NEW_FLOWISE_PORT="$2"; shift 2 ;;
    --bind-address) [[ $# -ge 2 ]] || fatal "$1 缺少值"; NEW_FLOWISE_BIND_ADDRESS="$2"; shift 2 ;;
    --app-url) [[ $# -ge 2 ]] || fatal "$1 缺少值"; NEW_APP_URL="$2"; shift 2 ;;
    --flowise-version) [[ $# -ge 2 ]] || fatal "$1 缺少值"; NEW_FLOWISE_VERSION="$2"; shift 2 ;;
    --pgvector-tag) [[ $# -ge 2 ]] || fatal "$1 缺少值"; NEW_PGVECTOR_IMAGE_TAG="$2"; shift 2 ;;
    --timezone) [[ $# -ge 2 ]] || fatal "$1 缺少值"; NEW_TZ="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fatal "未知參數：$1" ;;
  esac
done

valid_port "$NEW_FLOWISE_PORT" || fatal "連接埠必須為 1-65535。"
[[ "$NEW_FLOWISE_VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || fatal "Flowise tag 格式不正確。"
[[ "$NEW_PGVECTOR_IMAGE_TAG" =~ ^[A-Za-z0-9._-]+$ ]] || fatal "pgvector tag 格式不正確。"

if [[ -z "$NEW_APP_URL" ]]; then
  detect_ip() {
    local ip=""
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
    if [[ -z "$ip" ]]; then
      ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    [[ -n "$ip" ]] || ip="127.0.0.1"
    printf '%s' "$ip"
  }
  NEW_APP_URL="http://$(detect_ip):$NEW_FLOWISE_PORT"
fi
NEW_APP_URL="${NEW_APP_URL%/}"
NEW_SECURE_COOKIES=false
NEW_TRUST_PROXY=false
NEW_NUMBER_OF_PROXIES=0
if [[ "$NEW_APP_URL" == https://* ]]; then
  NEW_SECURE_COOKIES=true
  NEW_TRUST_PROXY=true
  NEW_NUMBER_OF_PROXIES=1
fi

cat <<EOF_WARN
============================================================
警告：即將全部刪掉重建 Flowise 測試環境
============================================================
會刪除：
  - 容器：flowise, flowise-postgres
  - Volume：flowise_data, flowise_pg_data
  - Network：flowise_net
  - 設定檔：$ENV_FILE
  - Flowise 內所有帳號、Chatflow、Agentflow、Credential、上傳檔案
  - PostgreSQL 內 flowise 與 flowise_vector 的所有資料

會重新產生：
  - PostgreSQL admin/app/vector 密碼
  - JWT、Session、Token Hash secret
  - FLOWISE_SECRETKEY_OVERWRITE

重建後設定：
  Flowise version : $NEW_FLOWISE_VERSION
  pgvector image  : $NEW_PGVECTOR_IMAGE_TAG
  URL             : $NEW_APP_URL
  Bind address    : $NEW_FLOWISE_BIND_ADDRESS
  Port            : $NEW_FLOWISE_PORT
  Timezone        : $NEW_TZ
EOF_WARN

if [[ "$PURGE_BACKUPS" == true ]]; then
  echo "  - 備份目錄：$INSTALL_DIR/backups"
else
  echo "會保留："
  echo "  - 備份目錄：$INSTALL_DIR/backups"
fi
if [[ "$REMOVE_IMAGES" == true ]]; then
  echo "也會刪除目前版本 image，之後重新下載。"
fi

echo "============================================================"
if [[ "$YES" != true ]]; then
  read -r -p "輸入 RESET-REBUILD 才繼續：" answer
  [[ "$answer" == "RESET-REBUILD" ]] || fatal "已取消。"
fi

old_flowise_image="flowiseai/flowise:${FLOWISE_VERSION:-$NEW_FLOWISE_VERSION}"
old_pgvector_image="pgvector/pgvector:${PGVECTOR_IMAGE_TAG:-$NEW_PGVECTOR_IMAGE_TAG}"

mkdir -p "$INSTALL_DIR/backups"

if [[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" ]]; then
  echo "停止並刪除 Compose 容器、網路與 Volume..."
  dc down -v --remove-orphans || true
fi

echo "清理殘留容器、Volume 與 Network..."
docker rm -f flowise flowise-postgres 2>/dev/null || true
docker volume rm   flowise_data   flowise_pg_data   flowise_postgres_data   flowise-pgvector_flowise_data   flowise-pgvector_flowise_pg_data   flowise-pgvector_postgres_data   2>/dev/null || true
docker network rm flowise_net flowise-pgvector_flowise_net 2>/dev/null || true

if [[ "$REMOVE_IMAGES" == true ]]; then
  docker image rm -f "$old_flowise_image" "$old_pgvector_image" 2>/dev/null || true
fi

if [[ "$PURGE_BACKUPS" == true ]]; then
  rm -rf "$INSTALL_DIR/backups"
fi
mkdir -p "$INSTALL_DIR/backups"
chmod 700 "$INSTALL_DIR/backups"

rm -f "$ENV_FILE"

echo "重新產生 .env 與所有密碼/金鑰..."
umask 077
cat > "$ENV_FILE" <<EOF_ENV
FLOWISE_VERSION=$NEW_FLOWISE_VERSION
PGVECTOR_IMAGE_TAG=$NEW_PGVECTOR_IMAGE_TAG
TZ=$NEW_TZ

FLOWISE_PORT=$NEW_FLOWISE_PORT
FLOWISE_BIND_ADDRESS=$NEW_FLOWISE_BIND_ADDRESS
APP_URL=$NEW_APP_URL
SECURE_COOKIES=$NEW_SECURE_COOKIES
TRUST_PROXY=$NEW_TRUST_PROXY
NUMBER_OF_PROXIES=$NEW_NUMBER_OF_PROXIES

POSTGRES_ADMIN_USER=flowise_admin
POSTGRES_ADMIN_PASSWORD=$(openssl rand -hex 32)
POSTGRES_DEFAULT_DB=postgres

FLOWISE_DB_NAME=flowise
FLOWISE_DB_USER=flowise_app
FLOWISE_DB_PASSWORD=$(openssl rand -hex 32)

VECTOR_DB_NAME=flowise_vector
VECTOR_DB_USER=flowise_vector
VECTOR_DB_PASSWORD=$(openssl rand -hex 32)

JWT_AUTH_TOKEN_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_TOKEN_SECRET=$(openssl rand -hex 32)
EXPRESS_SESSION_SECRET=$(openssl rand -hex 32)
TOKEN_HASH_SECRET=$(openssl rand -hex 32)
FLOWISE_SECRETKEY_OVERWRITE=$(openssl rand -hex 32)

FLOWISE_FILE_SIZE_LIMIT=${FLOWISE_FILE_SIZE_LIMIT:-100mb}
SHOW_COMMUNITY_NODES=${SHOW_COMMUNITY_NODES:-true}
DISABLE_FLOWISE_TELEMETRY=${DISABLE_FLOWISE_TELEMETRY:-true}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
EOF_ENV
chmod 600 "$ENV_FILE"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

echo "驗證 Compose 設定..."
dc config --quiet

echo "下載容器映像..."
dc pull

echo "啟動 PostgreSQL 與 pgvector..."
dc up -d postgres
if ! wait_healthy flowise-postgres 300; then
  dc logs --tail=200 postgres
  fatal "PostgreSQL 未通過健康檢查。"
fi

"$INSTALL_DIR/scripts/reconcile-db.sh"

echo "啟動 Flowise..."
dc up -d flowise
if ! wait_healthy flowise 420; then
  dc logs --tail=200 flowise
  fatal "Flowise 未通過健康檢查。"
fi

if ! "$INSTALL_DIR/scripts/verify.sh"; then
  echo "WARNING: 服務已啟動，但驗證有項目失敗；請執行 sudo flowise-ctl logs。" >&2
fi

cat <<EOF_DONE

============================================================
全部刪掉重建完成
============================================================
Flowise URL : $APP_URL
安裝目錄    : $INSTALL_DIR
狀態檢查    : sudo flowise-ctl status
完整驗證    : sudo flowise-ctl verify
pgvector 密碼: sudo flowise-ctl secret VECTOR_DB_PASSWORD
============================================================
EOF_DONE
