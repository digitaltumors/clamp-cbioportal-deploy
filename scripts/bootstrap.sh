#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

reuse_data=false
for arg in "$@"; do
  case "$arg" in
    --reuse-data) reuse_data=true ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

require_config
"$ROOT_DIR/scripts/prerequisites.sh"
project="$(project_name)"
mysql_volume="${project}_cbioportal_mysql_data"
mongo_volume="${project}_cbioportal_mongo_data"
if [[ "$reuse_data" != true ]] \
  && { docker volume inspect "$mysql_volume" >/dev/null 2>&1 \
    || docker volume inspect "$mongo_volume" >/dev/null 2>&1; }; then
  die "Persistent CLAMP volumes already exist; use --reuse-data only when that is intentional"
fi

"$ROOT_DIR/scripts/build.sh"
"$ROOT_DIR/scripts/up.sh"

if curl -fsS "$(base_url)/cbioportal/api/studies/clamp_2026" >/dev/null 2>&1; then
  if [[ "$reuse_data" == true ]]; then
    log "Existing clamp_2026 study retained"
  else
    die "Unexpected existing clamp_2026 study in a fresh bootstrap"
  fi
else
  "$ROOT_DIR/scripts/import-study.sh"
fi

"$ROOT_DIR/scripts/smoke-test.sh"
log "Bootstrap completed successfully: $(base_url)/test/"
