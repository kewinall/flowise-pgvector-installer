#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
PROJECT_NAME="flowise-pgvector-installer"
STAGING_DIR="dist/${PROJECT_NAME}-${VERSION}"
ARCHIVE_BASE="${PROJECT_NAME}-${VERSION}"

rm -rf dist
mkdir -p "$STAGING_DIR"

copy_item() {
  local path="$1"
  mkdir -p "$STAGING_DIR/$(dirname "$path")"
  cp -a "$path" "$STAGING_DIR/$path"
}

items=(
  README.md
  CHANGELOG.md
  LICENSE
  VERSION
  compose.yaml
  env.template
  .env.example
  install.sh
  uninstall.sh
  flowise-ctl
  .gitignore
  .gitattributes
  .editorconfig
  postgres-init
  scripts
  docs
)

for item in "${items[@]}"; do
  [[ -e "$item" ]] && copy_item "$item"
done

# CI-only files are useful in source repositories but not required in the installer package.
rm -rf "$STAGING_DIR/scripts/ci"

find "$STAGING_DIR" -type f \( -name '*.sh' -o -name 'install.sh' -o -name 'uninstall.sh' -o -name 'flowise-ctl' \) -exec chmod 0755 {} +
find "$STAGING_DIR" -type f ! \( -name '*.sh' -o -name 'install.sh' -o -name 'uninstall.sh' -o -name 'flowise-ctl' \) -exec chmod 0644 {} +

(
  cd dist
  tar -czf "${ARCHIVE_BASE}.tar.gz" "${ARCHIVE_BASE}"
  zip -qr "${ARCHIVE_BASE}.zip" "${ARCHIVE_BASE}"
  sha256sum "${ARCHIVE_BASE}.tar.gz" "${ARCHIVE_BASE}.zip" > "${ARCHIVE_BASE}-SHA256SUMS.txt"
)

echo "Created release artifacts under dist/:"
ls -lh dist/*.tar.gz dist/*.zip dist/*SHA256SUMS.txt
