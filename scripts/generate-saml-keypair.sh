#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

umask 077

force=false
[[ "${1:-}" == "--force" ]] && force=true
(( $# <= 1 )) || die "Usage: generate-saml-keypair.sh [--force]"
require_command openssl

directory="$ROOT_DIR/secrets/saml"
key="$directory/local.key"
certificate="$directory/local.crt"
mkdir -p "$directory"
if [[ -e "$key" || -e "$certificate" ]]; then
  [[ "$force" == true ]] || die "SAML key material already exists; use --force to rotate it"
fi

temporary_key="$(mktemp "${key}.XXXXXX")"
temporary_certificate="$(mktemp "${certificate}.XXXXXX")"
trap 'rm -f "$temporary_key" "$temporary_certificate"' EXIT
chmod 0600 "$temporary_key" "$temporary_certificate"
openssl req -newkey rsa:3072 -nodes -sha256 \
  -keyout "$temporary_key" -x509 -days 825 -out "$temporary_certificate" \
  -subj "/CN=CLAMP local cBioPortal SAML/O=CLAMP development"
install_generated_file "$temporary_key" "$key" 0600
install_generated_file "$temporary_certificate" "$certificate" 0644
log "Generated local SAML key pair"
openssl x509 -in "$certificate" -noout -fingerprint -sha256 -enddate
