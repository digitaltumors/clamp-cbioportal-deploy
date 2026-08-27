#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[[ "${1:-}" == "--local" && $# -eq 1 ]] || die "Usage: configure-auth.sh --local"
require_config
require_command openssl

admin_password="$(openssl rand -hex 24)"
test_password="$(openssl rand -hex 16)"

python3 - "$ENV_FILE" "$admin_password" "$test_password" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
updates = {
    "AUTH_MODE": "saml",
    "KEYCLOAK_VERSION": "26.2.4",
    "PUBLIC_BASE_URL": "http://localhost:8088",
    "SAML_REGISTRATION_ID": "cbio-saml-idp",
    "SAML_ENTITY_ID": "clamp-cbioportal",
    "SAML_IDP_ORIGIN": "http://localhost:8081",
    "SAML_ALLOW_NULL_ORIGIN": "true",
    "SESSION_SERVICE_INSTANCE": "clamp_portal",
    "KEYCLOAK_PORT": "8081",
    "KEYCLOAK_REALM": "clamp",
    "KEYCLOAK_ADMIN_USERNAME": "admin",
    "AUTH_TEST_USERNAME": "testuser",
    "KEYCLOAK_ADMIN_PASSWORD": sys.argv[2],
    "AUTH_TEST_PASSWORD": sys.argv[3],
}
lines = path.read_text().splitlines()
seen = set()
output = []
generated_secret_keys = {"KEYCLOAK_ADMIN_PASSWORD", "AUTH_TEST_PASSWORD"}
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        key, value = line.split("=", 1)
        if key == "CBIOPORTAL_JAVA_OPTS":
            value = re.sub(r"\s*-Dauthenticate=\S+", "", value).strip()
            line = f"{key}={value}"
        elif key in updates:
            if key not in generated_secret_keys or not value:
                line = f"{key}={updates[key]}"
            seen.add(key)
    output.append(line)
for key, value in updates.items():
    if key not in seen:
        output.append(f"{key}={value}")
path.write_text("\n".join(output) + "\n")
path.chmod(0o600)
PY

if [[ ! -f "$ROOT_DIR/secrets/saml/local.key" || ! -f "$ROOT_DIR/secrets/saml/local.crt" ]]; then
  "$ROOT_DIR/scripts/generate-saml-keypair.sh"
fi
"$ROOT_DIR/scripts/render-auth-config.sh"

log "Starting local Keycloak to obtain its SAML metadata"
compose up -d keycloak
metadata_url="http://localhost:$(env_value KEYCLOAK_PORT)/realms/$(env_value KEYCLOAK_REALM)/protocol/saml/descriptor"
wait_for_url "$metadata_url" 300 || {
  compose logs --tail=150 keycloak >&2 || true
  die "Keycloak did not become ready"
}
"$ROOT_DIR/scripts/fetch-idp-metadata.sh"
"$ROOT_DIR/scripts/render-config.sh"

log "Local SAML authentication configured"
log "Test username: $(env_value AUTH_TEST_USERNAME)"
log "Keycloak: http://localhost:$(env_value KEYCLOAK_PORT)"
log "Run ./scripts/up.sh to recreate cBioPortal in authenticated mode"
