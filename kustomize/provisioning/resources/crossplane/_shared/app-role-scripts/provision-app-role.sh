#!/usr/bin/env bash
# shellcheck disable=SC2154  # pg_* vars are Flux postBuild.substitute placeholders, not shell vars
set -euo pipefail

if [ -f /shared/skip ]; then
  echo "Skipping, nothing to provision this tick."
  exit 0
fi

ADDRESS=$(cat /shared/address)
ADMIN_USER=$(cat /shared/admin-username)
APP_PASSWORD=$(cat /shared/app-password)
NEEDS_PASSWORD_SET=false
if [ -f /shared/needs-password-set ]; then
  NEEDS_PASSWORD_SET=true
fi

PGPASSWORD=$(cat /shared/admin-password) psql -h "$ADDRESS" -U "$ADMIN_USER" \
  -d "${pg_database_name}" -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${pg_database_name}_app') THEN
    CREATE ROLE "${pg_database_name}_app" WITH LOGIN PASSWORD '$APP_PASSWORD';
  ELSIF $NEEDS_PASSWORD_SET THEN
    ALTER ROLE "${pg_database_name}_app" WITH PASSWORD '$APP_PASSWORD';
  END IF;
END
\$\$;
GRANT "${pg_database_name}_app" TO "$ADMIN_USER";
ALTER DATABASE "${pg_database_name}" OWNER TO "${pg_database_name}_app";
${pg_grant_sql}
SQL
