#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
realm="$(env_value KEYCLOAK_REALM)"
port="$(env_value KEYCLOAK_PORT)"
url="${IDP_METADATA_URL:-http://localhost:${port:-8081}/realms/${realm:-clamp}/protocol/saml/descriptor}"
destination="$ROOT_DIR/secrets/saml/idp-metadata.xml"
mkdir -p "$(dirname "$destination")"
temporary="$destination.tmp"

case "$url" in
  http://localhost:*|http://127.0.0.1:*|https://*) ;;
  *) die "Refusing insecure metadata URL outside localhost: $url" ;;
esac

curl -fsS --max-time 30 "$url" -o "$temporary"
python3 - "$temporary" "$(env_value KEYCLOAK_REALM)" <<'PY'
import pathlib
import sys
import xml.etree.ElementTree as ET

path = pathlib.Path(sys.argv[1])
realm = sys.argv[2]
root = ET.parse(path).getroot()
entity_id = root.attrib.get("entityID", "")
if not entity_id or realm not in entity_id:
    raise SystemExit(f"Unexpected SAML metadata entityID: {entity_id!r}")
if "X509Certificate" not in path.read_text():
    raise SystemExit("SAML metadata contains no signing certificate")
PY
install_generated_file "$temporary" "$destination" 0644
log "Stored validated IdP metadata at $destination"
