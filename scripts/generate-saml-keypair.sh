#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

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

umask 077
openssl req -newkey rsa:3072 -nodes -sha256 \
  -keyout "$key.tmp" -x509 -days 825 -out "$certificate.tmp" \
  -subj "/CN=CLAMP local cBioPortal SAML/O=CLAMP development"
chmod 0600 "$key.tmp"
chmod 0644 "$certificate.tmp"
mv "$key.tmp" "$key"
mv "$certificate.tmp" "$certificate"
log "Generated local SAML key pair"
openssl x509 -in "$certificate" -noout -fingerprint -sha256 -enddate
