#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
require_command docker
report_dir="$ROOT_DIR/reports/security"
mkdir -p "$report_dir/sbom" "$report_dir/trivy-cache"
chmod 0700 "$report_dir" "$report_dir/sbom" "$report_dir/trivy-cache"

images=(
  "$(env_value CLAMP_CBIOPORTAL_IMAGE)"
  "$(env_value CLAMP_STUDY_LOADER_IMAGE)"
  "$(env_value CLAMP_WEB_IMAGE)"
  "$(env_value CLAMP_SESSION_SERVICE_IMAGE)"
  "$(env_value CLAMP_MYSQL_IMAGE)"
  "docker.io/mongo:$(env_value MONGO_VERSION)"
  "$(env_value CLAMP_KEYCLOAK_IMAGE)"
)
for image in "${images[@]}"; do
  docker image inspect "$image" >/dev/null 2>&1 || docker pull "$image"
done

syft_image='ghcr.io/anchore/syft:v1.51.1@sha256:95fe0835e5bebc6f8b1f8acef68d47d63d594ef4c0f25c097ff853b23cbac74c'
trivy_image='docker.io/aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969'
: > "$report_dir/images.tsv"
printf 'scanned_at_utc\timage\tdigest\n' >> "$report_dir/images.tsv"
scan_failed=false
for image in "${images[@]}"; do
  key="$(printf '%s' "$image" | tr '/:@' '____')"
  digest="$(docker image inspect --format '{{index .RepoDigests 0}}' "$image" 2>/dev/null || true)"
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$image" "${digest:-local-build}" >> "$report_dir/images.tsv"
  log "Generating SBOM for $image"
  if command -v syft >/dev/null 2>&1; then
    syft "$image" -o "spdx-json=$report_dir/sbom/$key.spdx.json"
  else
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
      "$syft_image" "$image" -o spdx-json > "$report_dir/sbom/$key.spdx.json"
  fi
  log "Scanning $image (HIGH and CRITICAL fail the release)"
  if command -v trivy >/dev/null 2>&1; then
    trivy image --exit-code 1 --scanners vuln --severity HIGH,CRITICAL --format json \
      --output "$report_dir/$key.trivy.json" "$image" || scan_failed=true
  else
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
      -v "$report_dir/trivy-cache:/root/.cache/trivy" \
      "$trivy_image" image --exit-code 1 --scanners vuln --severity HIGH,CRITICAL \
      --format json "$image" > "$report_dir/$key.trivy.json" || scan_failed=true
  fi
done
chmod 0600 "$report_dir/images.tsv" "$report_dir"/*.json "$report_dir/sbom"/*.json
[[ "$scan_failed" == false ]] \
  || die "One or more images contain HIGH/CRITICAL findings; review reports/security before release"
log "All seven deployable images passed mandatory HIGH/CRITICAL scanning"
