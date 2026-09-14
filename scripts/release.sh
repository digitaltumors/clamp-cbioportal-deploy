#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
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
require_command shellcheck
shellcheck -x -P SCRIPTDIR "$ROOT_DIR"/scripts/*.sh "$ROOT_DIR"/study-loader/*.sh "$ROOT_DIR"/database/mongo/*.sh
compose config --quiet
"$ROOT_DIR/scripts/build.sh"
"$ROOT_DIR/scripts/scan-images.sh"
if [[ "$integration" == true ]]; then "$ROOT_DIR/scripts/bootstrap.sh"; fi
if [[ "$push" == true ]]; then
  registry="$(env_value IMAGE_REGISTRY)"
  [[ -n "$registry" ]] || die "IMAGE_REGISTRY must be set for --push"
  for key in CLAMP_CBIOPORTAL_IMAGE CLAMP_STUDY_LOADER_IMAGE CLAMP_WEB_IMAGE CLAMP_SESSION_SERVICE_IMAGE CLAMP_MYSQL_IMAGE CLAMP_KEYCLOAK_IMAGE; do
    image="$(env_value "$key")"; remote="${registry%/}/${image}"
    docker tag "$image" "$remote"; docker push "$remote"
  done
fi
log "Release checks completed"
