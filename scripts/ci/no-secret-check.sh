#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ ! -f .env ]] || fail ".env must not be committed. Use env.template or .env.example only."

# Avoid committing generated database dumps or local backups by mistake.
if find . -path './.git' -prune -o \( -name '*.dump' -o -name '*.sql' -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' \) -print | grep -q .; then
  find . -path './.git' -prune -o \( -name '*.dump' -o -name '*.sql' -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' \) -print
  fail "archive, SQL, or dump files should not be committed; attach generated packages to releases instead."
fi

# Basic heuristic: known generated secret keys should not contain real hex secrets in example files.
for file in env.template .env.example; do
  [[ -f "$file" ]] || continue
  grep -Eq 'PASSWORD=CHANGE_ME|SECRET=CHANGE_ME|SECRETKEY_OVERWRITE=CHANGE_ME' "$file" || \
    fail "$file must keep placeholder secret values."
done
