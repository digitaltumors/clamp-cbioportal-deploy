#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
require_command docker
require_command curl
require_command python3
command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 \
  || die "Either sha256sum or shasum is required"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required"
docker info >/dev/null 2>&1 || die "Cannot access the Docker daemon"

study_dir="$(study_data_path)"
for path in \
  compose.yaml \
  cbioportal/Dockerfile \
  study-loader/Dockerfile \
  session-service/Dockerfile \
  database/mysql/Dockerfile \
  auth/keycloak/Dockerfile \
  web/Dockerfile \
  database/init/cgds.sql \
  database/init/seed.sql.gz \
  database/mongo/init-session-user.sh; do
  [[ -e "$ROOT_DIR/$path" ]] || die "Required file is missing: $path"
done
for path in meta_study.txt data_clinical_sample.txt data_mutations.txt; do
  [[ -f "$study_dir/$path" ]] || die "Required study file is missing: $study_dir/$path"
done

for key in MONGO_ROOT_USERNAME MONGO_ROOT_PASSWORD MONGO_APP_USERNAME MONGO_APP_PASSWORD; do
  [[ -n "$(env_value "$key")" ]] || die "Missing $key; regenerate or update .env"
done
for key in CBIOPORTAL_VERSION SESSION_SERVICE_VERSION SESSION_JAVA_RUNTIME_VERSION MYSQL_VERSION GOSU_BUILDER_VERSION MONGO_VERSION NGINX_VERSION KEYCLOAK_VERSION; do
  [[ "$(env_value "$key")" == *@sha256:* ]] \
    || die "$key must include a reviewed immutable sha256 manifest digest"
done

mode="$(auth_mode)"
idp_mode="$(auth_idp_mode)"
bind_address="$(env_value BIND_ADDRESS)"
bind_address="${bind_address:-127.0.0.1}"
case "$mode" in
  false|saml) ;;
  *) die "AUTH_MODE must be false or saml" ;;
esac
case "$idp_mode" in
  local|external) ;;
  *) die "AUTH_IDP_MODE must be local or external" ;;
esac

if [[ "$mode" == "saml" ]]; then
  require_command openssl
  for path in secrets/saml/idp-metadata.xml secrets/saml/local.crt secrets/saml/local.key; do
    [[ -f "$ROOT_DIR/$path" ]] || die "SAML authentication file is missing: $path"
  done
  if [[ "$idp_mode" == "local" ]]; then
    [[ -f "$ROOT_DIR/runtime/keycloak-realm.json" ]] \
      || die "Local Keycloak realm is missing; run configure-auth.sh --local"
  else
    [[ "$(env_value SAML_ALLOW_NULL_ORIGIN)" == "false" ]] \
      || die "External SAML requires SAML_ALLOW_NULL_ORIGIN=false"
    [[ "$(env_value SAML_IDP_ORIGIN)" == https://* ]] \
      || die "External SAML requires an HTTPS SAML_IDP_ORIGIN"
  fi
  key_mode="$(file_mode "$ROOT_DIR/secrets/saml/local.key")"
  [[ "$key_mode" == "600" ]] || die "SAML private key must have mode 600, found $key_mode"
  openssl x509 -checkend $((30 * 86400)) -noout -in "$ROOT_DIR/secrets/saml/local.crt" >/dev/null \
    || die "SAML certificate expires in less than 30 days"
fi

case "$bind_address" in
  127.0.0.1|localhost|::1) ;;
  *) die "BIND_ADDRESS must remain loopback-only; publish through a trusted local TLS ingress" ;;
esac
if [[ "$(env_value PUBLIC_BASE_URL)" == https://* ]]; then
  [[ "$mode" == "saml" && "$idp_mode" == "external" ]] \
    || die "HTTPS production URLs require SAML with an external identity provider"
  [[ "$(env_value TRUSTED_TLS_PROXY)" == "true" ]] \
    || die "HTTPS production URLs require TRUSTED_TLS_PROXY=true"
  [[ -n "$(env_value BACKUP_AGE_RECIPIENT)" ]] \
    || die "HTTPS production URLs require BACKUP_AGE_RECIPIENT for encrypted backups"
fi
case "$(env_value DEV_BIND_ADDRESS)" in
  ""|127.0.0.1|localhost|::1) ;;
  *) die "DEV_BIND_ADDRESS must remain loopback-only" ;;
esac

available_kb="$(df -Pk "$ROOT_DIR" | awk 'NR == 2 {print $4}')"
required_kb=$((10 * 1024 * 1024))
(( available_kb >= required_kb )) || die "At least 10 GiB of free disk space is required"
log "Prerequisites passed"
