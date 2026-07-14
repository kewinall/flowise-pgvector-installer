#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
need_root
load_env

required=(
  POSTGRES_ADMIN_USER POSTGRES_DEFAULT_DB
  FLOWISE_DB_NAME FLOWISE_DB_USER FLOWISE_DB_PASSWORD
  VECTOR_DB_NAME VECTOR_DB_USER VECTOR_DB_PASSWORD
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    fatal "missing environment variable: ${name}"
  fi
done

echo "同步 PostgreSQL role/database 與目前 .env 密碼..."

# Use local Unix socket inside the PostgreSQL container. With the official image,
# local access from inside the container is allowed for the bootstrap superuser,
# even if the host password in .env was regenerated after the data volume already existed.
dc exec -T postgres \
  psql \
  -U "$POSTGRES_ADMIN_USER" \
  -d "$POSTGRES_DEFAULT_DB" \
  -v ON_ERROR_STOP=1 \
  -v flowise_db_name="$FLOWISE_DB_NAME" \
  -v flowise_db_user="$FLOWISE_DB_USER" \
  -v flowise_db_password="$FLOWISE_DB_PASSWORD" \
  -v vector_db_name="$VECTOR_DB_NAME" \
  -v vector_db_user="$VECTOR_DB_USER" \
  -v vector_db_password="$VECTOR_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'flowise_db_user', :'flowise_db_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'flowise_db_user')\gexec

SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'flowise_db_user', :'flowise_db_password')\gexec

SELECT format('CREATE DATABASE %I OWNER %I ENCODING %L', :'flowise_db_name', :'flowise_db_user', 'UTF8')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'flowise_db_name')\gexec

SELECT format('ALTER DATABASE %I OWNER TO %I', :'flowise_db_name', :'flowise_db_user')\gexec
SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', :'flowise_db_name', :'flowise_db_user')\gexec

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'vector_db_user', :'vector_db_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'vector_db_user')\gexec

SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'vector_db_user', :'vector_db_password')\gexec

SELECT format('CREATE DATABASE %I OWNER %I ENCODING %L', :'vector_db_name', :'vector_db_user', 'UTF8')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'vector_db_name')\gexec

SELECT format('ALTER DATABASE %I OWNER TO %I', :'vector_db_name', :'vector_db_user')\gexec
SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', :'vector_db_name', :'vector_db_user')\gexec
SQL

# Ensure the Flowise app user can create and migrate tables in the Flowise DB.
dc exec -T postgres \
  psql \
  -U "$POSTGRES_ADMIN_USER" \
  -d "$FLOWISE_DB_NAME" \
  -v ON_ERROR_STOP=1 \
  -v flowise_db_user="$FLOWISE_DB_USER" <<'SQL'
GRANT USAGE, CREATE ON SCHEMA public TO :"flowise_db_user";
ALTER SCHEMA public OWNER TO :"flowise_db_user";
SQL

# Ensure pgvector is available and the vector user can create vector tables.
dc exec -T postgres \
  psql \
  -U "$POSTGRES_ADMIN_USER" \
  -d "$VECTOR_DB_NAME" \
  -v ON_ERROR_STOP=1 \
  -v vector_db_user="$VECTOR_DB_USER" <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
GRANT USAGE, CREATE ON SCHEMA public TO :"vector_db_user";
ALTER SCHEMA public OWNER TO :"vector_db_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO :"vector_db_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO :"vector_db_user";
SQL

echo "測試 flowise_app 密碼連線..."
dc exec -T -e PGPASSWORD="$FLOWISE_DB_PASSWORD" postgres \
  psql \
  -h 127.0.0.1 \
  -U "$FLOWISE_DB_USER" \
  -d "$FLOWISE_DB_NAME" \
  -v ON_ERROR_STOP=1 \
  -Atc "SELECT current_database() || ':' || current_user;"

echo "測試 flowise_vector 密碼連線..."
dc exec -T -e PGPASSWORD="$VECTOR_DB_PASSWORD" postgres \
  psql \
  -h 127.0.0.1 \
  -U "$VECTOR_DB_USER" \
  -d "$VECTOR_DB_NAME" \
  -v ON_ERROR_STOP=1 \
  -Atc "SELECT current_database() || ':' || current_user;"

echo "PostgreSQL role/database 同步完成。"
