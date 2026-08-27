#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
[[ "$(auth_mode)" == "saml" ]] || die "AUTH_MODE is not saml"
base="$(base_url)"
registration="$(env_value SAML_REGISTRATION_ID)"
keycloak_port="$(env_value KEYCLOAK_PORT)"
tmp_headers="$(mktemp)"
tmp_body="$(mktemp)"
trap 'rm -f "$tmp_headers" "$tmp_body"' EXIT

curl -fsS "$base/healthz" | grep -q '^ok$' || die "nginx is unhealthy"
curl -fsS "$base/cbioportal/api/health" >/dev/null || die "cBioPortal health endpoint is unavailable"
curl -fsS "http://localhost:${keycloak_port}/realms/$(env_value KEYCLOAK_REALM)/protocol/saml/descriptor" \
  | grep -q 'EntityDescriptor' || die "Keycloak SAML metadata is unavailable"

curl -sS -D "$tmp_headers" -o "$tmp_body" \
  "$base/cbioportal/saml2/authenticate/$registration"
if grep -Eq '^HTTP/[^ ]+ 30[23]' "$tmp_headers"; then
  grep -qi "^location: http://localhost:${keycloak_port}/" "$tmp_headers" \
    || die "SAML redirect did not target local Keycloak"
else
  grep -qi "<form action=\"http://localhost:${keycloak_port}/" "$tmp_body" \
    || die "SAML POST binding did not target local Keycloak"
  grep -q 'name="SAMLRequest"' "$tmp_body" || die "SAML POST form contains no request"
fi

grep -q '^authenticate=saml$' "$ROOT_DIR/runtime/application.properties" \
  || die "Rendered portal config is not in SAML mode"
grep -q '^session.service.url=http://cbioportal-session:5001/api/sessions/' "$ROOT_DIR/runtime/application.properties" \
  || die "Session service is not configured"
expected_cors_origins="$(env_value SAML_IDP_ORIGIN)"
if [[ "$(env_value SAML_ALLOW_NULL_ORIGIN)" == "true" ]]; then
  expected_cors_origins+=",null"
fi
grep -q "^security.cors.allowed-origins=${expected_cors_origins}$" "$ROOT_DIR/runtime/application.properties" \
  || die "SAML browser origins are not allowed by cBioPortal CORS"
log "SAML configuration and redirect tests passed"
