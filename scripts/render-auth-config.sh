#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

umask 077

require_config
[[ "$(env_value AUTH_MODE)" == "saml" && "$(auth_idp_mode)" == "local" ]] || exit 0

python3 - "$ENV_FILE" "$ROOT_DIR/auth/keycloak/realm-template.json" \
  "$ROOT_DIR/runtime/keycloak-realm.json" <<'PY'
import json
import os
import pathlib
import sys

env_path, template_path, output_path = map(pathlib.Path, sys.argv[1:])
values = {}
for raw in env_path.read_text().splitlines():
    if not raw or raw.lstrip().startswith("#") or "=" not in raw:
        continue
    key, value = raw.split("=", 1)
    values[key] = value

required = ("KEYCLOAK_REALM", "SAML_ENTITY_ID", "PUBLIC_BASE_URL", "SAML_REGISTRATION_ID", "AUTH_TEST_USERNAME", "AUTH_TEST_PASSWORD")
missing = [key for key in required if not values.get(key)]
if missing:
    raise SystemExit("Missing auth values: " + ", ".join(missing))

rendered = template_path.read_text()
for key in required:
    rendered = rendered.replace("${" + key + "}", values[key])
parsed = json.loads(rendered)
content = json.dumps(parsed, indent=2) + "\n"
destination = pathlib.Path(output_path)
if destination.exists() and destination.read_text() == content:
    destination.chmod(0o600)
elif destination.exists():
    # Preserve the inode used by Docker Desktop/WSL file bind mounts.
    with destination.open("w") as output:
        output.write(content)
        output.flush()
else:
    import tempfile
    handle, temporary_name = tempfile.mkstemp(prefix=destination.name + ".", dir=destination.parent)
    os.fchmod(handle, 0o600)
    os.close(handle)
    temporary = pathlib.Path(temporary_name)
    temporary.write_text(content)
    temporary.chmod(0o600)
    temporary.replace(destination)
destination.chmod(0o600)
PY
