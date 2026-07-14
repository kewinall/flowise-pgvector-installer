#!/usr/bin/env bash
set -Eeuo pipefail

required=(
  POSTGRES_USER POSTGRES_DB
  FLOWISE_DB_NAME FLOWISE_DB_USER FLOWISE_DB_PASSWORD
  VECTOR_DB_NAME VECTOR_DB_USER VECTOR_DB_PASSWORD
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: missing environment variable: ${name}" >&2
    exit 1
  fi
done

echo "Creating or reconciling Flowise application and vector databases..."

psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set=ON_ERROR_STOP=1 \
  --set=flowise_db_name="$FLOWISE_DB_NAME" \
  --set=flowise_db_user="$FLOWISE_DB_USER" \
  --set=flowise_db_password="$FLOWISE_DB_PASSWORD" \
  --set=vector_db_name="$VECTOR_DB_NAME" \
  --set=vector_db_user="$VECTOR_DB_USER" \
  --set=vector_db_password="$VECTOR_DB_PASSWORD" <<'EOSQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'flowise_db_user', :'flowise_db_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'flowise_db_user')\gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'flowise_db_user', :'flowise_db_password')\gexec
SELECT format('CREATE DATABASE %I OWNER %I ENCODING %L', :'flowise_db_name', :'flowise_db_user', 'UTF8')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'flowise_db_name')\gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'flowise_db_name', :'flowise_db_user')\gexec

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'vector_db_user', :'vector_db_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'vector_db_user')\gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'vector_db_user', :'vector_db_password')\gexec
SELECT format('CREATE DATABASE %I OWNER %I ENCODING %L', :'vector_db_name', :'vector_db_user', 'UTF8')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'vector_db_name')\gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'vector_db_name', :'vector_db_user')\gexec
EOSQL

psql --username "$POSTGRES_USER" --dbname "$FLOWISE_DB_NAME" --set=ON_ERROR_STOP=1 \
  --set=flowise_db_user="$FLOWISE_DB_USER" <<'EOSQL'
GRANT USAGE, CREATE ON SCHEMA public TO :"flowise_db_user";
ALTER SCHEMA public OWNER TO :"flowise_db_user";
EOSQL

psql --username "$POSTGRES_USER" --dbname "$VECTOR_DB_NAME" --set=ON_ERROR_STOP=1 \
  --set=vector_db_user="$VECTOR_DB_USER" <<'EOSQL'
CREATE EXTENSION IF NOT EXISTS vector;
GRANT USAGE, CREATE ON SCHEMA public TO :"vector_db_user";
ALTER SCHEMA public OWNER TO :"vector_db_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO :"vector_db_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO :"vector_db_user";
EOSQL

echo "PostgreSQL and pgvector initialization completed."
