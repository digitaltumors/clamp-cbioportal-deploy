#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

force=false
for arg in "$@"; do
  case "$arg" in
    --force) force=true ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

require_config
ensure_reports_dir
"$ROOT_DIR/scripts/up.sh"

export IMAGE_REVISION="$(image_revision)"
export STUDY_VERSION="$(study_hash)"
marker="$ROOT_DIR/reports/last-import.env"
study_url="$(base_url)/cbioportal/api/studies/clamp_2026"
study_exists=false
if curl -fsS "$study_url" >/dev/null 2>&1; then
  study_exists=true
fi

if [[ -f "$marker" || "$study_exists" == true ]]; then
  if [[ "$force" != true ]]; then
    die "clamp_2026 is already imported or has an import record; use --force for an intentional overwrite"
  fi
  log "A deliberate overwrite was requested"
fi

compose --profile tools run --rm study-loader import
compose restart cbioportal
wait_for_url "$(base_url)/cbioportal/api/health" 300 \
  || die "cBioPortal did not recover after import"
if [[ "$(auth_mode)" == "saml" ]]; then
  "$ROOT_DIR/scripts/test-auth-login.py" "$ROOT_DIR"
else
  curl -fsS "$study_url" | grep -q '"studyId"[[:space:]]*:[[:space:]]*"clamp_2026"' \
    || die "Import completed but clamp_2026 was not returned by the studies API"
fi

tmp_marker="$marker.tmp"
{
  printf 'STUDY_ID=clamp_2026\n'
  printf 'STUDY_VERSION=%s\n' "$STUDY_VERSION"
  printf 'IMAGE_REVISION=%s\n' "$IMAGE_REVISION"
  printf 'IMPORTED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$tmp_marker"
mv "$tmp_marker" "$marker"
log "Imported clamp_2026 at study version ${STUDY_VERSION:0:12}"
