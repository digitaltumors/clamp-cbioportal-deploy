#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command docker
require_command curl
command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 \
  || die "Either sha256sum or shasum is required"
require_command python3

docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required"
docker info >/dev/null 2>&1 || die "Cannot access the Docker daemon"

for path in \
  compose.yaml \
  cbioportal/Dockerfile \
  study-loader/Dockerfile \
  web/Dockerfile \
  studies/clamp_2026/meta_study.txt \
  studies/clamp_2026/data_clinical_sample.txt \
  studies/clamp_2026/data_mutations.txt \
  database/init/cgds.sql \
  database/init/seed.sql.gz; do
  [[ -e "$ROOT_DIR/$path" ]] || die "Required file is missing: $path"
done

if [[ -f "$ENV_FILE" && "$(auth_mode)" == "saml" ]]; then
  for path in secrets/saml/idp-metadata.xml secrets/saml/local.crt secrets/saml/local.key runtime/keycloak-realm.json; do
    [[ -f "$ROOT_DIR/$path" ]] || die "SAML authentication file is missing: $path; run configure-auth.sh --local"
  done
  key_mode="$(file_mode "$ROOT_DIR/secrets/saml/local.key")"
  [[ "$key_mode" == "600" ]] || die "SAML private key must have mode 600, found $key_mode"
  openssl x509 -checkend $((30 * 86400)) -noout -in "$ROOT_DIR/secrets/saml/local.crt" >/dev/null \
    || die "SAML certificate expires in less than 30 days"
fi

available_kb="$(df -Pk "$ROOT_DIR" | awk 'NR == 2 {print $4}')"
required_kb=$((10 * 1024 * 1024))
(( available_kb >= required_kb )) || die "At least 10 GiB of free disk space is required"

log "Prerequisites passed"
