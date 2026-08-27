#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
ensure_reports_dir
"$ROOT_DIR/scripts/up.sh"
export IMAGE_REVISION="$(image_revision)"
export STUDY_VERSION="$(study_hash)"
log "Validating clamp_2026 (${STUDY_VERSION:0:12})"
compose --profile tools run --rm study-loader validate
