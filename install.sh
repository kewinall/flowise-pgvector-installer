#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/flowise-pgvector"
FLOWISE_VERSION="3.1.3"
PGVECTOR_IMAGE_TAG="0.8.4-pg17-bookworm"
FLOWISE_PORT="3000"
FLOWISE_BIND_ADDRESS="0.0.0.0"
APP_URL=""
TZ="Asia/Taipei"
OPEN_FIREWALL=true
SKIP_DOCKER_INSTALL=false
RESET_REBUILD=false
RESET_YES=false
RESET_PURGE_BACKUPS=false
RESET_REMOVE_IMAGES=false

usage() {
  cat <<'EOF'
Rocky Linux 9：Flowise + PostgreSQL + pgvector 一鍵安裝

用法：sudo bash install.sh [選項]

  --install-dir PATH          安裝目錄，預設 /opt/flowise-pgvector
  --port PORT                 Flowise 對外連接埠，預設 3000
  --bind-address IP           綁定位置，預設 0.0.0.0；反向代理可用 127.0.0.1
  --app-url URL               Flowise 對外網址；未指定時自動使用主機 IP
  --flowise-version VERSION   Flowise image tag，預設 3.1.3
  --pgvector-tag TAG          pgvector image tag，預設 0.8.4-pg17-bookworm
  --timezone TZ               時區，預設 Asia/Taipei
  --no-firewall               不調整 firewalld
  --skip-docker-install       假設 Docker 與 Compose 已安裝
  --reset-rebuild             測試環境用：先刪除既有容器、Volume、.env 後重新安裝
  --yes                       搭配 --reset-rebuild，不要求互動確認
  --purge-backups             搭配 --reset-rebuild，同時刪除 backups
  --remove-images             搭配 --reset-rebuild，同時刪除目前版本 image
  -h, --help                  顯示說明
EOF
}

fatal() {
  echo "ERROR: $*" >&2
  exit 1
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 ))
}

unset_flowise_env_vars() {
  local names=(
    FLOWISE_VERSION PGVECTOR_IMAGE_TAG TZ
    FLOWISE_PORT FLOWISE_BIND_ADDRESS APP_URL SECURE_COOKIES TRUST_PROXY NUMBER_OF_PROXIES
    POSTGRES_ADMIN_USER POSTGRES_ADMIN_PASSWORD POSTGRES_DEFAULT_DB
    FLOWISE_DB_NAME FLOWISE_DB_USER FLOWISE_DB_PASSWORD
    VECTOR_DB_NAME VECTOR_DB_USER VECTOR_DB_PASSWORD
    JWT_AUTH_TOKEN_SECRET JWT_REFRESH_TOKEN_SECRET EXPRESS_SESSION_SECRET TOKEN_HASH_SECRET FLOWISE_SECRETKEY_OVERWRITE
    FLOWISE_FILE_SIZE_LIMIT SHOW_COMMUNITY_NODES DISABLE_FLOWISE_TELEMETRY BACKUP_RETENTION_DAYS
  )
  local name
  for name in "${names[@]}"; do
    unset "$name" || true
  done
}

reload_env_file() {
  # Docker Compose interpolation gives exported shell variables higher precedence than --env-file.
  # Reload .env immediately before Compose operations to prevent stale exported passwords.
  unset_flowise_env_vars
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

while (( $# > 0 )); do
  case "$1" in
    --install-dir) [[ $# -ge 2 ]] || fatal "$1 缺少值"; INSTALL_DIR="$2"; shift 2 ;;
    --port) [[ $# -ge 2 ]] || fatal "$1 缺少值"; FLOWISE_PORT="$2"; shift 2 ;;
    --bind-address) [[ $# -ge 2 ]] || fatal "$1 缺少值"; FLOWISE_BIND_ADDRESS="$2"; shift 2 ;;
    --app-url) [[ $# -ge 2 ]] || fatal "$1 缺少值"; APP_URL="$2"; shift 2 ;;
    --flowise-version) [[ $# -ge 2 ]] || fatal "$1 缺少值"; FLOWISE_VERSION="$2"; shift 2 ;;
    --pgvector-tag) [[ $# -ge 2 ]] || fatal "$1 缺少值"; PGVECTOR_IMAGE_TAG="$2"; shift 2 ;;
    --timezone) [[ $# -ge 2 ]] || fatal "$1 缺少值"; TZ="$2"; shift 2 ;;
    --no-firewall) OPEN_FIREWALL=false; shift ;;
    --skip-docker-install) SKIP_DOCKER_INSTALL=true; shift ;;
    --reset-rebuild) RESET_REBUILD=true; shift ;;
    --yes) RESET_YES=true; shift ;;
    --purge-backups) RESET_PURGE_BACKUPS=true; shift ;;
    --remove-images) RESET_REMOVE_IMAGES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fatal "未知參數：$1" ;;
  esac
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || fatal "請使用 sudo bash install.sh 執行。"
valid_port "$FLOWISE_PORT" || fatal "連接埠必須為 1-65535。"
[[ "$INSTALL_DIR" == /* ]] || fatal "--install-dir 必須是絕對路徑。"
[[ "$FLOWISE_VERSION" =~ ^[A-Za-z0-9._-]+$ ]] || fatal "Flowise tag 格式不正確。"
[[ "$PGVECTOR_IMAGE_TAG" =~ ^[A-Za-z0-9._-]+$ ]] || fatal "pgvector tag 格式不正確。"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "rocky" || "${VERSION_ID%%.*}" != "9" ]]; then
    echo "WARNING: 此安裝包以 Rocky Linux 9 驗證；目前為 ${PRETTY_NAME:-unknown}." >&2
  fi
fi

EXISTING_INSTALL=false
if [[ -f "$INSTALL_DIR/.env" ]]; then
  EXISTING_INSTALL=true
  echo "偵測到既有安裝，將保留 .env 與既有資料設定。"
  set -a
  # shellcheck disable=SC1090
  source "$INSTALL_DIR/.env"
  set +a
  FLOWISE_BIND_ADDRESS="${FLOWISE_BIND_ADDRESS:-0.0.0.0}"
  FLOWISE_PORT="${FLOWISE_PORT:-3000}"
  APP_URL="${APP_URL:-}"
fi

if [[ "$EXISTING_INSTALL" == false ]] && ss -lntH "sport = :$FLOWISE_PORT" 2>/dev/null | grep -q .; then
  fatal "連接埠 $FLOWISE_PORT 已被使用。"
fi

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "Docker 與 Compose 已安裝。"
    systemctl enable --now docker
    return
  fi

  [[ "$SKIP_DOCKER_INSTALL" == false ]] || fatal "找不到 Docker/Compose，但已指定 --skip-docker-install。"

  echo "安裝 Docker Engine 與 Compose plugin..."
  dnf -y install dnf-plugins-core ca-certificates curl openssl tar gzip

  # 移除會與 Docker CE / containerd.io 衝突的舊套件；不移除 Podman 本體。
  dnf -y remove \
    docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine \
    podman-docker runc >/dev/null 2>&1 || true

  if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
    dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
  fi

  dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

reset_existing_install() {
  cat <<EOF
============================================================
警告：即將全部刪掉重建 Flowise 測試環境
============================================================
會刪除：
  - 容器：flowise, flowise-postgres
  - Volume：flowise_data, flowise_pg_data
  - Network：flowise_net
  - 設定檔：$INSTALL_DIR/.env
  - Flowise 內所有帳號、流程、Credential、上傳檔案
  - PostgreSQL 內所有 Flowise 與 pgvector 資料
EOF
  if [[ "$RESET_PURGE_BACKUPS" == true ]]; then
    echo "  - 備份目錄：$INSTALL_DIR/backups"
  else
    echo "會保留：$INSTALL_DIR/backups"
  fi
  if [[ "$RESET_REMOVE_IMAGES" == true ]]; then
    echo "也會刪除目前版本 image，之後重新下載。"
  fi
  echo "============================================================"

  if [[ "$RESET_YES" != true ]]; then
    read -r -p "輸入 RESET-REBUILD 才繼續：" answer
    [[ "$answer" == "RESET-REBUILD" ]] || fatal "已取消。"
  fi

  local old_flowise_image="flowiseai/flowise:${FLOWISE_VERSION:-3.1.3}"
  local old_pgvector_image="pgvector/pgvector:${PGVECTOR_IMAGE_TAG:-0.8.4-pg17-bookworm}"

  if [[ -f "$INSTALL_DIR/.env" && -f "$INSTALL_DIR/compose.yaml" ]]; then
    docker compose --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" down -v --remove-orphans || true
  fi
  docker rm -f flowise flowise-postgres 2>/dev/null || true
  docker volume rm     flowise_data     flowise_pg_data     flowise_postgres_data     flowise-pgvector_flowise_data     flowise-pgvector_flowise_pg_data     flowise-pgvector_postgres_data     2>/dev/null || true
  docker network rm flowise_net flowise-pgvector_flowise_net 2>/dev/null || true

  if [[ "$RESET_REMOVE_IMAGES" == true ]]; then
    docker image rm -f "$old_flowise_image" "$old_pgvector_image" 2>/dev/null || true
  fi

  if [[ "$RESET_PURGE_BACKUPS" == true ]]; then
    rm -rf "$INSTALL_DIR/backups"
  fi
  rm -f "$INSTALL_DIR/.env"
  EXISTING_INSTALL=false
}

install_docker

if [[ "$RESET_REBUILD" == true ]]; then
  reset_existing_install
fi

if [[ "$EXISTING_INSTALL" == false ]]; then
  for container_name in flowise flowise-postgres; do
    if docker container inspect "$container_name" >/dev/null 2>&1; then
      fatal "已存在名稱為 $container_name 的容器。請先確認或移除既有容器。"
    fi
  done
fi

for cmd in openssl curl tar; do
  command -v "$cmd" >/dev/null 2>&1 || dnf -y install "$cmd"
done

detect_ip() {
  local ip=""
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  [[ -n "$ip" ]] || ip="127.0.0.1"
  printf '%s' "$ip"
}

if [[ -z "$APP_URL" ]]; then
  APP_URL="http://$(detect_ip):$FLOWISE_PORT"
fi
APP_URL="${APP_URL%/}"
SECURE_COOKIES=false
TRUST_PROXY=false
NUMBER_OF_PROXIES=0
if [[ "$APP_URL" == https://* ]]; then
  SECURE_COOKIES=true
  TRUST_PROXY=true
  NUMBER_OF_PROXIES=1
fi

mkdir -p "$INSTALL_DIR/postgres-init" "$INSTALL_DIR/scripts" "$INSTALL_DIR/backups"
chmod 700 "$INSTALL_DIR/backups"

copy_file() {
  local rel="$1"
  install -m "${2:-0644}" "$SOURCE_DIR/$rel" "$INSTALL_DIR/$rel"
}
copy_file compose.yaml 0644
copy_file env.template 0600
copy_file flowise-ctl 0750
copy_file uninstall.sh 0750
copy_file postgres-init/01-init-databases.sh 0750
copy_file scripts/common.sh 0750
copy_file scripts/backup.sh 0750
copy_file scripts/restore.sh 0750
copy_file scripts/verify.sh 0750
copy_file scripts/reconcile-db.sh 0750
copy_file scripts/reset-rebuild.sh 0750
[[ -f "$SOURCE_DIR/README.md" ]] && copy_file README.md 0644
[[ -f "$SOURCE_DIR/CHANGELOG.md" ]] && copy_file CHANGELOG.md 0644

ENV_FILE="$INSTALL_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  echo "保留既有 .env，不重新產生密碼。"
else
  if docker volume inspect flowise_pg_data >/dev/null 2>&1; then
    fatal "偵測到既有 flowise_pg_data，但缺少 $ENV_FILE。為避免密碼不一致，已停止。"
  fi

  umask 077
  cat > "$ENV_FILE" <<EOF
FLOWISE_VERSION=$FLOWISE_VERSION
PGVECTOR_IMAGE_TAG=$PGVECTOR_IMAGE_TAG
TZ=$TZ

FLOWISE_PORT=$FLOWISE_PORT
FLOWISE_BIND_ADDRESS=$FLOWISE_BIND_ADDRESS
APP_URL=$APP_URL
SECURE_COOKIES=$SECURE_COOKIES
TRUST_PROXY=$TRUST_PROXY
NUMBER_OF_PROXIES=$NUMBER_OF_PROXIES

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

FLOWISE_FILE_SIZE_LIMIT=100mb
SHOW_COMMUNITY_NODES=true
DISABLE_FLOWISE_TELEMETRY=true
BACKUP_RETENTION_DAYS=30
EOF
  chmod 600 "$ENV_FILE"
fi

reload_env_file

ln -sfn "$INSTALL_DIR/flowise-ctl" /usr/local/bin/flowise-ctl

if [[ "$OPEN_FIREWALL" == true ]] && [[ "$FLOWISE_BIND_ADDRESS" != "127.0.0.1" && "$FLOWISE_BIND_ADDRESS" != "::1" ]]; then
  if systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "開放 firewalld TCP/$FLOWISE_PORT..."
    firewall-cmd --permanent --add-port="$FLOWISE_PORT/tcp"
    firewall-cmd --reload
  else
    echo "firewalld 未啟用，略過防火牆設定。"
  fi
fi

cd "$INSTALL_DIR"
echo "驗證 Compose 設定..."
docker compose --env-file .env -f compose.yaml config --quiet

echo "下載容器映像..."
docker compose --env-file .env -f compose.yaml pull

echo "啟動 PostgreSQL 與 pgvector..."
docker compose --env-file .env -f compose.yaml up -d postgres

wait_healthy() {
  local container="$1"
  local timeout="${2:-360}"
  local elapsed=0 state
  while (( elapsed < timeout )); do
    state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || true)"
    printf '\r等待 %-18s：%-10s (%3ss/%3ss)' "$container" "${state:-starting}" "$elapsed" "$timeout"
    case "$state" in
      healthy|running) echo; return 0 ;;
      unhealthy|exited|dead) echo; return 1 ;;
    esac
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo
  return 1
}

if ! wait_healthy flowise-postgres 300; then
  docker compose --env-file .env -f compose.yaml logs --tail=200 postgres
  fatal "PostgreSQL 未通過健康檢查。"
fi

"$INSTALL_DIR/scripts/reconcile-db.sh"

echo "啟動 Flowise..."
docker compose --env-file .env -f compose.yaml up -d flowise

if ! wait_healthy flowise 420; then
  docker compose --env-file .env -f compose.yaml logs --tail=200 flowise
  fatal "Flowise 未通過健康檢查。"
fi

if ! "$INSTALL_DIR/scripts/verify.sh"; then
  echo "WARNING: 服務已啟動，但驗證有項目失敗；請執行 sudo flowise-ctl logs。" >&2
fi

cat <<EOF

============================================================
安裝完成
============================================================
Flowise URL : $APP_URL
安裝目錄    : $INSTALL_DIR
管理指令    : sudo flowise-ctl help
狀態檢查    : sudo flowise-ctl status
完整驗證    : sudo flowise-ctl verify
建立備份    : sudo flowise-ctl backup

Flowise 內設定 Postgres Vector Store：
  Host      : postgres
  Port      : 5432
  Database  : flowise_vector
  User      : flowise_vector
  Password  : sudo flowise-ctl secret VECTOR_DB_PASSWORD
  SSL       : false

首次開啟 Flowise 時，請依畫面建立管理員帳號。
PostgreSQL 5432 未對主機或外部網路開放。
============================================================
EOF
