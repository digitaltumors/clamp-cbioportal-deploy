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


sed_in_place() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    # BSD sed, including the macOS version, requires a backup suffix.
    sed -i '' "$@"
  fi
}

canonical_path() {
  python3 - "$1" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
}

file_mode() {
  if stat -c %a "$1" >/dev/null 2>&1; then
    stat -c %a "$1"
  else
    stat -f %Lp "$1"
  fi
}


install_generated_file() {
  local source="$1"
  local destination="$2"
  local mode="$3"
  if [[ -e "$destination" ]]; then
    # Preserve the inode used by Docker Desktop/WSL file bind mounts.
    cp "$source" "$destination"
    rm "$source"
  else
    mv "$source" "$destination"
  fi
  chmod "$mode" "$destination"
}

sha256_files() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

verify_sha256_manifest() {
  local manifest="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$manifest"
  else
    shasum -a 256 -c "$manifest"
  fi
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


study_exists_in_database() {
  local study_id="$1"
  local query
  local count
  [[ "$study_id" =~ ^[A-Za-z0-9_.-]+$ ]] \
    || die "Invalid study identifier for database lookup: $study_id"
  query="SELECT COUNT(*) FROM cancer_study WHERE CANCER_STUDY_IDENTIFIER = '${study_id}';"
  # Credentials and the query intentionally expand inside the database container.
  # shellcheck disable=SC2016
  if ! count="$(compose exec -T cbioportal-database sh -c \
    'export MYSQL_PWD="$MYSQL_PASSWORD"; exec mysql -u"$MYSQL_USER" "$MYSQL_DATABASE" --batch --skip-column-names --execute="$1"' \
    sh "$query")"; then
    die "Could not query cBioPortal for study $study_id"
  fi
  [[ "$count" =~ ^[0-9]+$ ]] \
    || die "Unexpected database result while checking study $study_id: $count"
  (( count > 0 ))
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
  python3 - "$ROOT_DIR" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
study = root / "studies" / "clamp_2026"
records = []
for path in study.rglob("*"):
    if not path.is_file():
        continue
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    records.append((path.relative_to(root).as_posix(), digest.hexdigest()))
payload = "".join(
    f"{digest}  {relative}\n" for relative, digest in sorted(records)
).encode()
print(hashlib.sha256(payload).hexdigest())
PY
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
