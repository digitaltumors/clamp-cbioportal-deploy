#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:-}"
study_dir="${STUDY_DIR:-/study/clamp_2026}"
portal_url="${PORTAL_URL:-http://cbioportal:8080/cbioportal}"
reports_dir="${REPORTS_DIR:-/reports}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
auth_mode="${AUTH_MODE:-false}"

portal_args=(-u "$portal_url")
if [[ "$auth_mode" != "false" ]]; then
  # SAML protects /api/info, which validateData.py and metaImport.py query
  # before doing any work. The official -n mode skips only portal-dependent
  # metadata checks; study-file validation and database import still run.
  portal_args=(-n)
fi

mkdir -p "$reports_dir"

validate() {
  local report="$reports_dir/validate-${timestamp}.log"
  local validator_status
  echo "Validating ${study_dir}; report: ${report}"
  set +e
  validateData.py -s "$study_dir" "${portal_args[@]}" -v 2>&1 | tee "$report"
  validator_status="${PIPESTATUS[0]}"
  set -e
  if (( validator_status != 0 )); then
    if grep -q '^Validation of data succeeded with warnings\.$' "$report"; then
      echo "Validator returned ${validator_status}; continuing because it reported success with warnings."
    else
      echo "Dataset validation failed with status ${validator_status}." >&2
      return "$validator_status"
    fi
  fi
}

import_study() {
  local report="$reports_dir/import-${timestamp}.html"
  validate
  echo "Importing ${study_dir}; report: ${report}"
  metaImport.py -s "$study_dir" "${portal_args[@]}" -o -html "$report" \
    -jvo "${IMPORT_JAVA_OPTS:--Xms1g -Xmx8g}"
}

case "$action" in
  validate)
    validate
    ;;
  import)
    import_study
    ;;
  *)
    echo "Usage: import-study {validate|import}" >&2
    exit 64
    ;;
esac
