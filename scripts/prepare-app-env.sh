#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../app"
if [[ -e .env ]]; then echo '.env exists; preserved'; exit 0; fi
umask 077
set -o noclobber
printf 'POSTGRES_DB=app\nPOSTGRES_USER=app\nPOSTGRES_PASSWORD=%s\nDB_HOST=db\n' "$(openssl rand -hex 32)" > .env
echo 'Environment file created with mode 600'
