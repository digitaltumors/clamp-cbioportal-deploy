#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
"$ROOT_DIR/scripts/render-auth-config.sh"
"$ROOT_DIR/scripts/render-config.sh"
"$ROOT_DIR/scripts/prerequisites.sh"

services=(cbioportal-database cbioportal web)
if [[ "$(auth_mode)" == "saml" ]]; then
  services=(cbioportal-database cbioportal-session-database cbioportal-session cbioportal web)
  if [[ "$(auth_idp_mode)" == "local" ]]; then
    compose up -d keycloak
    keycloak_url="http://localhost:$(env_value KEYCLOAK_PORT)/realms/$(env_value KEYCLOAK_REALM)/protocol/saml/descriptor"
    wait_for_url "$keycloak_url" 300 || die "Keycloak SAML metadata endpoint did not become ready"
    "$ROOT_DIR/scripts/fetch-idp-metadata.sh"
    "$ROOT_DIR/scripts/render-config.sh"
  fi
fi

compose up -d "${services[@]}"
if ! wait_for_url "$(base_url)/healthz" 120; then
  compose ps
  compose logs --tail=200 web >&2 || true
  die "Web service did not become healthy"
fi
startup_timeout="$(env_value CBIOPORTAL_STARTUP_TIMEOUT)"
startup_timeout="${startup_timeout:-600}"
if ! wait_for_url "$(base_url)/cbioportal/api/health" "$startup_timeout"; then
  compose ps
  compose logs --tail=200 cbioportal cbioportal-database >&2 || true
  die "cBioPortal did not become healthy; inspect the logs above for database, memory, permission, or SELinux errors"
fi
log "CLAMP is running at $(base_url)/test/"
if [[ "$(auth_mode)" == "saml" ]]; then
  log "SAML authentication is enabled through $(env_value SAML_IDP_ORIGIN)"
fi
