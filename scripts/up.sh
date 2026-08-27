#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
"$ROOT_DIR/scripts/render-auth-config.sh"
"$ROOT_DIR/scripts/render-config.sh"
"$ROOT_DIR/scripts/prerequisites.sh"

if [[ "$(auth_mode)" == "saml" ]]; then
  compose up -d keycloak
  keycloak_url="http://localhost:$(env_value KEYCLOAK_PORT)/realms/$(env_value KEYCLOAK_REALM)/protocol/saml/descriptor"
  wait_for_url "$keycloak_url" 300 || die "Keycloak SAML metadata endpoint did not become ready"
fi

compose up -d cbioportal-database cbioportal-session-database cbioportal-session cbioportal web
if ! wait_for_url "$(base_url)/healthz" 420; then
  compose ps
  compose logs --tail=100 cbioportal web >&2 || true
  die "Web service did not become healthy"
fi
wait_for_url "$(base_url)/cbioportal/api/health" 120 \
  || die "cBioPortal health endpoint did not become ready"
log "CLAMP is running at $(base_url)/test/"
if [[ "$(auth_mode)" == "saml" ]]; then
  log "SAML authentication is enabled through http://localhost:$(env_value KEYCLOAK_PORT)"
fi
