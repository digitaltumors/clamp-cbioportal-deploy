#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[[ -f "$ENV_FILE" ]] || die "Missing .env"
mkdir -p "$ROOT_DIR/runtime"

python3 - "$ENV_FILE" "$ROOT_DIR/cbioportal/application.properties" \
  "$ROOT_DIR/runtime/application.properties" <<'PY'
import pathlib
import sys

env_path, template_path, output_path = map(pathlib.Path, sys.argv[1:])
values = {}
for raw_line in env_path.read_text().splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    values[key] = value

required = ("DB_MYSQL_URL", "DB_MYSQL_USERNAME", "DB_MYSQL_PASSWORD")
missing = [key for key in required if not values.get(key)]
if missing:
    raise SystemExit("Missing required .env values: " + ", ".join(missing))

rendered = template_path.read_text()
for key in required:
    placeholder = "${" + key + "}"
    if placeholder not in rendered:
        raise SystemExit(f"Template placeholder missing: {placeholder}")
    rendered = rendered.replace(placeholder, values[key])

mode = values.get("AUTH_MODE", "false") or "false"
if mode not in {"false", "saml"}:
    raise SystemExit(f"Unsupported AUTH_MODE: {mode}")

lines = [line for line in rendered.splitlines() if not line.startswith("authenticate=")]
rendered = "\n".join(lines) + "\n"
if mode == "false":
    auth_properties = {
        "authenticate": "false",
        "authorization": "false",
        "session.service.url": "",
    }
else:
    auth_required = (
        "SAML_REGISTRATION_ID", "SAML_ENTITY_ID", "SAML_IDP_ORIGIN",
        "SESSION_SERVICE_INSTANCE",
    )
    missing_auth = [key for key in auth_required if not values.get(key)]
    if missing_auth:
        raise SystemExit("Missing auth values: " + ", ".join(missing_auth))
    registration = values["SAML_REGISTRATION_ID"]
    cors_origins = [values["SAML_IDP_ORIGIN"]]
    allow_null_origin = values.get("SAML_ALLOW_NULL_ORIGIN", "false").lower()
    if allow_null_origin not in {"true", "false"}:
        raise SystemExit("SAML_ALLOW_NULL_ORIGIN must be true or false")
    if allow_null_origin == "true":
        cors_origins.append("null")
    auth_properties = {
        "authenticate": "saml",
        "authorization": "false",
        "session.service.url": f"http://cbioportal-session:5001/api/sessions/{values['SESSION_SERVICE_INSTANCE']}/",
        f"spring.security.saml2.relyingparty.registration.{registration}.assertingparty.metadata-uri": "classpath:/idp-metadata.xml",
        f"spring.security.saml2.relyingparty.registration.{registration}.entity-id": values["SAML_ENTITY_ID"],
        f"spring.security.saml2.relyingparty.registration.{registration}.signing.credentials[0].certificate-location": "classpath:/local.crt",
        f"spring.security.saml2.relyingparty.registration.{registration}.signing.credentials[0].private-key-location": "classpath:/local.key",
        f"spring.security.saml2.relyingparty.registration.{registration}.singlelogout.binding": "POST",
        "security.cors.allowed-origins": ",".join(cors_origins),
        "filter_groups_by_appname": "false",
        "security.method_authorization_enabled": "false",
    }

existing_keys = {line.split("=", 1)[0] for line in rendered.splitlines() if "=" in line and not line.lstrip().startswith("#")}
for key, value in auth_properties.items():
    if key in existing_keys:
        rendered = "\n".join(
            f"{key}={value}" if line.startswith(key + "=") else line
            for line in rendered.splitlines()
        ) + "\n"
    else:
        rendered += f"{key}={value}\n"

destination = pathlib.Path(output_path)
temporary = destination.with_suffix(".tmp")
temporary.write_text(rendered)
temporary.chmod(0o600)
temporary.replace(destination)
PY
