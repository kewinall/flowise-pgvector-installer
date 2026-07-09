#!/usr/bin/env bash
set -Eeuo pipefail

resolve_dir() {
  local source_path="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  while [[ -L "$source_path" ]]; do
    source_path="$(readlink -f "$source_path")"
  done
  cd "$(dirname "$source_path")/.." && pwd
}

INSTALL_DIR="${FLOWISE_INSTALL_DIR:-$(resolve_dir)}"
ENV_FILE="$INSTALL_DIR/.env"
COMPOSE_FILE="$INSTALL_DIR/compose.yaml"

fatal() {
  echo "ERROR: $*" >&2
  exit 1
}

need_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || fatal "請使用 sudo 執行。"
}

need_install() {
  [[ -f "$ENV_FILE" ]] || fatal "找不到 $ENV_FILE；請先執行 install.sh。"
  [[ -f "$COMPOSE_FILE" ]] || fatal "找不到 $COMPOSE_FILE。"
  command -v docker >/dev/null 2>&1 || fatal "找不到 Docker。"
  docker compose version >/dev/null 2>&1 || fatal "找不到 Docker Compose plugin。"
}

load_env() {
  need_install
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

dc() {
  docker compose --project-directory "$INSTALL_DIR" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

wait_healthy() {
  local container="$1"
  local timeout="${2:-300}"
  local elapsed=0
  local state
  while (( elapsed < timeout )); do
    state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || true)"
    case "$state" in
      healthy|running)
        return 0
        ;;
      unhealthy|exited|dead)
        return 1
        ;;
    esac
    sleep 5
    elapsed=$((elapsed + 5))
  done
  return 1
}
