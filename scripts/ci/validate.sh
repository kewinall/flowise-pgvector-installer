#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

echo "==> Validate required files"
required_files=(
  install.sh
  uninstall.sh
  flowise-ctl
  compose.yaml
  env.template
  .env.example
  postgres-init/01-init-databases.sh
  scripts/common.sh
  scripts/backup.sh
  scripts/restore.sh
  scripts/verify.sh
  scripts/reconcile-db.sh
  scripts/reset-rebuild.sh
)
for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || fail "missing required file: $file"
done

echo "==> Validate executable bits"
executable_files=(
  install.sh
  uninstall.sh
  flowise-ctl
  postgres-init/01-init-databases.sh
  scripts/common.sh
  scripts/backup.sh
  scripts/restore.sh
  scripts/verify.sh
  scripts/reconcile-db.sh
  scripts/reset-rebuild.sh
  scripts/ci/validate.sh
  scripts/ci/package.sh
  scripts/ci/no-secret-check.sh
)
for file in "${executable_files[@]}"; do
  [[ -x "$file" ]] || fail "$file must be executable"
done

echo "==> Bash syntax check"
while IFS= read -r file; do
  bash -n "$file"
done < <(find . -type f \( -name '*.sh' -o -name 'install.sh' -o -name 'uninstall.sh' -o -name 'flowise-ctl' \) | sort)

if command -v shellcheck >/dev/null 2>&1; then
  echo "==> ShellCheck"
  shellcheck -x install.sh uninstall.sh flowise-ctl scripts/*.sh scripts/ci/*.sh postgres-init/*.sh
else
  echo "WARN: shellcheck not found; skipping ShellCheck." >&2
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "==> Docker Compose config validation"
  docker compose --env-file .env.example -f compose.yaml config --quiet
else
  echo "WARN: docker compose not found; skipping compose config validation." >&2
fi

if command -v python3 >/dev/null 2>&1; then
  echo "==> YAML parse check"
  python3 - <<'PY'
from pathlib import Path
try:
    import yaml
except Exception as exc:
    print(f"WARN: PyYAML unavailable; skipped YAML parse check: {exc}")
    raise SystemExit(0)
for file in [Path('compose.yaml'), Path('.github/workflows/ci.yml'), Path('.github/workflows/release.yml')]:
    if file.exists():
        with file.open('r', encoding='utf-8') as f:
            yaml.safe_load(f)
PY
fi

scripts/ci/no-secret-check.sh

echo "Validation completed."
