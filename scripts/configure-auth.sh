#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

umask 077
mode="${1:-}"
metadata_url="${2:-}"
case "$mode" in
  --local) (( $# == 1 )) || die "Usage: configure-auth.sh --local" ;;
  --external)
    (( $# == 2 )) || die "Usage: configure-auth.sh --external HTTPS_METADATA_URL"
    [[ "$metadata_url" == https://* ]] || die "External IdP metadata must use HTTPS"
    ;;
  *) die "Usage: configure-auth.sh --local | --external HTTPS_METADATA_URL" ;;
esac
require_config
require_command openssl
export CLAMP_AUTH_IDP_MODE="${mode#--}" CLAMP_KEYCLOAK_ADMIN_PASSWORD="" CLAMP_AUTH_TEST_PASSWORD=""
if [[ "$mode" == "--local" ]]; then
  CLAMP_KEYCLOAK_ADMIN_PASSWORD="$(openssl rand -hex 24)"
  CLAMP_AUTH_TEST_PASSWORD="$(openssl rand -hex 16)"
  export CLAMP_KEYCLOAK_ADMIN_PASSWORD CLAMP_AUTH_TEST_PASSWORD
fi
python3 - "$ENV_FILE" <<'PY'
import os
import pathlib
import re
import sys
path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
current = {}
for raw in lines:
    if "=" in raw and not raw.lstrip().startswith("#"):
        key, value = raw.split("=", 1)
        current[key] = value
idp_mode = os.environ["CLAMP_AUTH_IDP_MODE"]
updates = {"AUTH_MODE": "saml", "AUTH_IDP_MODE": idp_mode,
           "SAML_ALLOW_NULL_ORIGIN": "true" if idp_mode == "local" else "false",
           "SESSION_SERVICE_INSTANCE": "clamp_portal"}
if idp_mode == "local":
    web_port = current.get("WEB_PORT") or "45000"
    keycloak_port = current.get("KEYCLOAK_PORT") or "46000"
    updates.update({"KEYCLOAK_VERSION": "26.7.4@sha256:82a77884f3af238beab1e7afd63b5f530e1b5c0590bd7aa60b40a40463e29b2c", "PUBLIC_BASE_URL": f"http://localhost:{web_port}",
        "SAML_REGISTRATION_ID": "cbio-saml-idp", "SAML_ENTITY_ID": "clamp-cbioportal",
        "SAML_IDP_ORIGIN": f"http://localhost:{keycloak_port}", "KEYCLOAK_PORT": keycloak_port,
        "KEYCLOAK_REALM": "clamp", "KEYCLOAK_ADMIN_USERNAME": "admin",
        "AUTH_TEST_USERNAME": "testuser", "KEYCLOAK_ADMIN_PASSWORD": os.environ["CLAMP_KEYCLOAK_ADMIN_PASSWORD"],
        "AUTH_TEST_PASSWORD": os.environ["CLAMP_AUTH_TEST_PASSWORD"]})
seen = set(); output = []
generated = {"KEYCLOAK_ADMIN_PASSWORD", "AUTH_TEST_PASSWORD"}
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        key, value = line.split("=", 1)
        if key == "CBIOPORTAL_JAVA_OPTS":
            value = re.sub(r"\s*-Dauthenticate=\S+", "", value).strip()
            line = f"{key}={value}"
        elif key in updates:
            if key not in generated or not value: line = f"{key}={updates[key]}"
            seen.add(key)
    output.append(line)
for key, value in updates.items():
    if key not in seen: output.append(f"{key}={value}")
path.write_text("\n".join(output) + "\n"); path.chmod(0o600)
PY
unset CLAMP_KEYCLOAK_ADMIN_PASSWORD CLAMP_AUTH_TEST_PASSWORD
if [[ ! -f "$ROOT_DIR/secrets/saml/local.key" || ! -f "$ROOT_DIR/secrets/saml/local.crt" ]]; then
  "$ROOT_DIR/scripts/generate-saml-keypair.sh"
fi
if [[ "$mode" == "--local" ]]; then
  "$ROOT_DIR/scripts/render-auth-config.sh"
  log "Starting local Keycloak to obtain its SAML metadata"
  compose up -d keycloak
  metadata_url="http://localhost:$(env_value KEYCLOAK_PORT)/realms/$(env_value KEYCLOAK_REALM)/protocol/saml/descriptor"
  wait_for_url "$metadata_url" 300 || { compose logs --tail=150 keycloak >&2 || true; die "Keycloak did not become ready"; }
fi
IDP_METADATA_URL="$metadata_url" "$ROOT_DIR/scripts/fetch-idp-metadata.sh"
"$ROOT_DIR/scripts/render-config.sh"
if [[ "$mode" == "--local" ]]; then
  log "Local SAML authentication configured"
  log "Test username: $(env_value AUTH_TEST_USERNAME)"
  log "Keycloak: http://localhost:$(env_value KEYCLOAK_PORT)"
else
  log "External SAML metadata installed. Set PUBLIC_BASE_URL, SAML_ENTITY_ID, and SAML_IDP_ORIGIN in .env, then run prerequisites.sh."
fi
log "Run ./scripts/up.sh to recreate cBioPortal in authenticated mode"
