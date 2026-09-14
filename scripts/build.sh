#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
"$ROOT_DIR/scripts/prerequisites.sh"

IMAGE_REVISION="$(image_revision)"
log "Building images at revision ${IMAGE_REVISION}"
if ! docker buildx version >/dev/null 2>&1; then
  log "Docker Buildx is unavailable; using Docker's legacy builder"
  export DOCKER_BUILDKIT=0
fi

docker build \
  --build-arg "CBIOPORTAL_BASE=cbioportal/cbioportal:$(env_value CBIOPORTAL_VERSION)" \
  --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
  -f "$ROOT_DIR/cbioportal/Dockerfile" \
  -t "$(env_value CLAMP_CBIOPORTAL_IMAGE)" "$ROOT_DIR/cbioportal"
docker build \
  --build-arg "CBIOPORTAL_BASE=cbioportal/cbioportal:$(env_value CBIOPORTAL_VERSION)" \
  --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
  -f "$ROOT_DIR/study-loader/Dockerfile" \
  -t "$(env_value CLAMP_STUDY_LOADER_IMAGE)" "$ROOT_DIR"
docker build \
  --build-arg "NGINX_BASE=nginx:$(env_value NGINX_VERSION)" \
  --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
  -f "$ROOT_DIR/web/Dockerfile" \
  -t "$(env_value CLAMP_WEB_IMAGE)" "$ROOT_DIR/web"
docker build \
  --build-arg "SESSION_SERVICE_BASE=cbioportal/session-service:$(env_value SESSION_SERVICE_VERSION)" \
  --build-arg "JAVA_RUNTIME_BASE=eclipse-temurin:$(env_value SESSION_JAVA_RUNTIME_VERSION)" \
  --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
  -f "$ROOT_DIR/session-service/Dockerfile" \
  -t "$(env_value CLAMP_SESSION_SERVICE_IMAGE)" "$ROOT_DIR/session-service"
docker build \
  --build-arg "MYSQL_BASE=mysql:$(env_value MYSQL_VERSION)" \
  --build-arg "GOSU_BUILDER=golang:$(env_value GOSU_BUILDER_VERSION)" \
  --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
  -f "$ROOT_DIR/database/mysql/Dockerfile" \
  -t "$(env_value CLAMP_MYSQL_IMAGE)" "$ROOT_DIR/database/mysql"
docker build \
  --build-arg "KEYCLOAK_BASE=quay.io/keycloak/keycloak:$(env_value KEYCLOAK_VERSION)" \
  --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
  -f "$ROOT_DIR/auth/keycloak/Dockerfile" \
  -t "$(env_value CLAMP_KEYCLOAK_IMAGE)" "$ROOT_DIR/auth/keycloak"
