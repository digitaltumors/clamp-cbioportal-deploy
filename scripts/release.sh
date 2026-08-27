#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

push=false
integration=false
for arg in "$@"; do
  case "$arg" in
    --push) push=true ;;
    --integration) integration=true ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

require_config
"$ROOT_DIR/scripts/prerequisites.sh"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/study-loader/*.sh
else
  log "shellcheck is not installed; skipping shell lint"
fi

compose config --quiet
"$ROOT_DIR/scripts/build.sh"

if command -v syft >/dev/null 2>&1; then
  mkdir -p "$ROOT_DIR/reports/sbom"
  for image_key in CLAMP_CBIOPORTAL_IMAGE CLAMP_STUDY_LOADER_IMAGE CLAMP_WEB_IMAGE; do
    image="$(env_value "$image_key")"
    syft "$image" -o "spdx-json=$ROOT_DIR/reports/sbom/${image_key}.spdx.json"
  done
else
  log "syft is not installed; skipping SBOM generation"
fi

if command -v trivy >/dev/null 2>&1; then
  for image_key in CLAMP_CBIOPORTAL_IMAGE CLAMP_STUDY_LOADER_IMAGE CLAMP_WEB_IMAGE; do
    trivy image --exit-code 1 --severity CRITICAL "$(env_value "$image_key")"
  done
else
  log "trivy is not installed; skipping vulnerability scan"
fi

if [[ "$integration" == true ]]; then
  "$ROOT_DIR/scripts/bootstrap.sh"
fi

if [[ "$push" == true ]]; then
  registry="$(env_value IMAGE_REGISTRY)"
  [[ -n "$registry" ]] || die "IMAGE_REGISTRY must be set for --push"
  for image_key in CLAMP_CBIOPORTAL_IMAGE CLAMP_STUDY_LOADER_IMAGE CLAMP_WEB_IMAGE; do
    image="$(env_value "$image_key")"
    remote="${registry%/}/${image}"
    docker tag "$image" "$remote"
    docker push "$remote"
  done
fi

log "Release checks completed"
