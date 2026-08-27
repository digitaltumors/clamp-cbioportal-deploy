#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

force=false
generate_secrets=false
for arg in "$@"; do
  case "$arg" in
    --force) force=true ;;
    --generate-secrets) generate_secrets=true ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

[[ ! -e "$ENV_FILE" || "$force" == true ]] || die ".env already exists; use --force to replace it"
cp "$ROOT_DIR/.env.example" "$ENV_FILE"

if [[ "$generate_secrets" == true ]]; then
  require_command openssl
  db_password="$(openssl rand -hex 24)"
  root_password="$(openssl rand -hex 24)"
  sed_in_place \
    -e "s/^DB_MYSQL_PASSWORD=.*/DB_MYSQL_PASSWORD=${db_password}/" \
    -e "s/^DB_MYSQL_ROOT_PASSWORD=.*/DB_MYSQL_ROOT_PASSWORD=${root_password}/" \
    "$ENV_FILE"
fi

sed_in_place \
  -e "s/^HOST_UID=.*/HOST_UID=$(id -u)/" \
  -e "s/^HOST_GID=.*/HOST_GID=$(id -g)/" \
  "$ENV_FILE"
chmod 0600 "$ENV_FILE"
"$ROOT_DIR/scripts/render-config.sh"

log "Created $ENV_FILE"
if [[ "$generate_secrets" == false ]]; then
  log "Replace CHANGE_ME values before running the stack"
fi
