#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
INSTALL_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
export FLOWISE_INSTALL_DIR="$INSTALL_DIR"
# shellcheck source=scripts/common.sh
source "$INSTALL_DIR/scripts/common.sh"
need_root
load_env

purge=false
yes=false
for arg in "$@"; do
  case "$arg" in
    --purge) purge=true ;;
    --yes) yes=true ;;
    -h|--help)
      echo "用法：sudo bash uninstall.sh [--purge] [--yes]"
      echo "預設僅移除容器與網路並保留 Volume；--purge 會刪除所有資料。"
      exit 0
      ;;
    *) fatal "未知參數：$arg" ;;
  esac
done

if [[ "$purge" == true ]]; then
  if [[ "$yes" != true ]]; then
    read -r -p "將永久刪除 Flowise 與 PostgreSQL Volume。輸入 PURGE：" answer
    [[ "$answer" == "PURGE" ]] || fatal "已取消。"
  fi
  dc down -v --remove-orphans
else
  dc down --remove-orphans
fi

rm -f /usr/local/bin/flowise-ctl
if [[ "$purge" == true ]]; then
  cd /
  rm -rf "$INSTALL_DIR"
  echo "已完整移除 Flowise、PostgreSQL 與資料 Volume。Docker Engine 未移除。"
else
  echo "容器已移除，資料 Volume 與安裝目錄仍保留。"
  echo "重新啟動：cd $INSTALL_DIR && sudo docker compose up -d"
fi
