#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="$ROOT_DIR/compose.yaml"
AUTH_COMPOSE_FILE="$ROOT_DIR/compose.auth.yaml"

log() {
  printf '[clamp] %s\n' "$*"
}

die() {
  printf '[clamp] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_config() {
  [[ -f "$ENV_FILE" ]] || die "Missing .env. Run ./scripts/configure.sh, then review .env."
  if grep -q 'CHANGE_ME' "$ENV_FILE"; then
    die ".env still contains CHANGE_ME values"
  fi
}

env_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$ENV_FILE"
}

compose() {
  local -a files=(--env-file "$ENV_FILE" -f "$COMPOSE_FILE")
  if [[ -f "$ENV_FILE" && "$(auth_mode)" != "false" ]]; then
    files+=(-f "$AUTH_COMPOSE_FILE")
  fi
  docker compose "${files[@]}" "$@"
}

auth_mode() {
  local value="false"
  if [[ -f "$ENV_FILE" ]]; then
    value="$(env_value AUTH_MODE)"
  fi
  printf '%s\n' "${value:-false}"
}

project_name() {
  local value
  value="$(env_value COMPOSE_PROJECT_NAME)"
  printf '%s\n' "${value:-clamp-cbioportal}"
}

web_port() {
  local value
  value="$(env_value WEB_PORT)"
  printf '%s\n' "${value:-8088}"
}

base_url() {
  printf 'http://localhost:%s\n' "$(web_port)"
}

study_hash() {
  (
    cd "$ROOT_DIR"
    find studies/clamp_2026 -type f -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 sha256sum \
      | sha256sum \
      | awk '{print $1}'
  )
}

image_revision() {
  git -C "$ROOT_DIR" rev-parse --short=12 HEAD 2>/dev/null || printf 'uncommitted\n'
}

wait_for_url() {
  local url="$1"
  local timeout_seconds="${2:-300}"
  local started="$SECONDS"
  log "Waiting up to ${timeout_seconds}s for ${url}"
  until curl -fsS "$url" >/dev/null 2>&1; do
    if (( SECONDS - started >= timeout_seconds )); then
      return 1
    fi
    sleep 2
  done
}

confirm() {
  local prompt="$1"
  if [[ "${CI:-}" == "true" ]]; then
    die "Interactive confirmation is disabled in CI; pass the documented explicit flag"
  fi
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

ensure_reports_dir() {
  mkdir -p "$ROOT_DIR/reports"
}
