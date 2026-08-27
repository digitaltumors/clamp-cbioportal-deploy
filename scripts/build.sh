#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
"$ROOT_DIR/scripts/prerequisites.sh"

IMAGE_REVISION="$(image_revision)"
STUDY_VERSION="$(study_hash)"
export IMAGE_REVISION STUDY_VERSION
log "Building images at revision ${IMAGE_REVISION}; study ${STUDY_VERSION:0:12}"

if compose build "$@"; then
  exit 0
else
  (( $# == 0 )) || die "Per-service build arguments require the Docker Buildx plugin"
  log "Compose/Buildx build failed; retrying with Docker's legacy builder"
  DOCKER_BUILDKIT=0 docker build \
    --build-arg "CBIOPORTAL_BASE=cbioportal/cbioportal:$(env_value CBIOPORTAL_VERSION)" \
    --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
    -f "$ROOT_DIR/cbioportal/Dockerfile" \
    -t "$(env_value CLAMP_CBIOPORTAL_IMAGE)" "$ROOT_DIR/cbioportal"
  DOCKER_BUILDKIT=0 docker build \
    --build-arg "CBIOPORTAL_BASE=cbioportal/cbioportal:$(env_value CBIOPORTAL_VERSION)" \
    --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
    --build-arg "STUDY_VERSION=$STUDY_VERSION" \
    -f "$ROOT_DIR/study-loader/Dockerfile" \
    -t "$(env_value CLAMP_STUDY_LOADER_IMAGE)" "$ROOT_DIR"
  DOCKER_BUILDKIT=0 docker build \
    --build-arg "NGINX_BASE=nginx:$(env_value NGINX_VERSION)" \
    --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
    -f "$ROOT_DIR/web/Dockerfile" \
    -t "$(env_value CLAMP_WEB_IMAGE)" "$ROOT_DIR/web"
fi
