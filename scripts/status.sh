#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
compose ps
printf '\nAuthentication mode: %s\n' "$(auth_mode)"
if [[ "$(auth_mode)" == "saml" ]]; then
  printf 'Identity provider: http://localhost:%s/realms/%s\n' "$(env_value KEYCLOAK_PORT)" "$(env_value KEYCLOAK_REALM)"
  openssl x509 -in "$ROOT_DIR/secrets/saml/local.crt" -noout -fingerprint -sha256 -enddate | sed 's/^/  /'
fi
printf '\nConfigured study hash: %s\n' "$(study_hash)"
if [[ -f "$ROOT_DIR/reports/last-import.env" ]]; then
  printf 'Last successful import:\n'
  sed 's/^/  /' "$ROOT_DIR/reports/last-import.env"
else
  printf 'Last successful import: none recorded\n'
fi
