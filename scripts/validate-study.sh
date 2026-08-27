#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
ensure_reports_dir
"$ROOT_DIR/scripts/up.sh"
IMAGE_REVISION="$(image_revision)"
STUDY_VERSION="$(study_hash)"
export IMAGE_REVISION STUDY_VERSION
log "Validating clamp_2026 (${STUDY_VERSION:0:12})"
compose --profile tools run --rm study-loader validate
