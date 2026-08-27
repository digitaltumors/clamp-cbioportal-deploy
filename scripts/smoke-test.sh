#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
"$ROOT_DIR/scripts/up.sh"
url="$(base_url)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -fsS "$url/healthz" | grep -q '^ok$' || die "nginx health check failed"
curl -fsS "$url/test/" | grep -q 'cBioPortal Embed Test' || die "Custom website was not served"
curl -fsS "$url/test/" | grep -q 'id="cbio-auth-panel"' \
  || die "Custom website authentication panel is missing"
curl -fsS "$url/cbioportal/api/health" >/dev/null || die "Portal health check failed"
curl -sSI "$url/cbioportal/" > "$tmp_dir/headers"
grep -qi "content-security-policy: frame-ancestors 'self'" "$tmp_dir/headers" \
  || die "Expected iframe Content-Security-Policy is missing"

if [[ "$(auth_mode)" == "saml" ]]; then
  "$ROOT_DIR/scripts/test-auth-config.sh"
  "$ROOT_DIR/scripts/test-auth-login.py" "$ROOT_DIR"
  compose restart cbioportal
  wait_for_url "$url/cbioportal/api/health" 300 || die "Portal failed after authenticated restart"
  "$ROOT_DIR/scripts/test-auth-config.sh"
  "$ROOT_DIR/scripts/test-auth-login.py" "$ROOT_DIR"
  log "Authenticated smoke tests passed"
  exit 0
fi

curl -fsS "$url/cbioportal/api/studies/clamp_2026" > "$tmp_dir/study.json"
curl -fsS "$url/cbioportal/api/studies/clamp_2026/samples?projection=ID" > "$tmp_dir/samples.json"
curl -fsS "$url/cbioportal/api/studies/clamp_2026/molecular-profiles" > "$tmp_dir/profiles.json"
curl -fsS "$url/cbioportal/api/studies/clamp_2026/sample-lists" > "$tmp_dir/sample-lists.json"

python3 - "$tmp_dir" "$ROOT_DIR/tests/expected-study.json" <<'PY'
import json
import pathlib
import sys

tmp = pathlib.Path(sys.argv[1])
expected = json.loads(pathlib.Path(sys.argv[2]).read_text())
study = json.loads((tmp / "study.json").read_text())
samples = json.loads((tmp / "samples.json").read_text())
profiles = json.loads((tmp / "profiles.json").read_text())
sample_lists = json.loads((tmp / "sample-lists.json").read_text())

assert study["studyId"] == expected["study_id"], study
assert len(samples) == expected["sample_count"], len(samples)
assert expected["molecular_profile_id"] in {
    item["molecularProfileId"] for item in profiles
}, profiles
assert expected["case_list_id"] in {
    item["sampleListId"] for item in sample_lists
}, sample_lists
PY

compose restart cbioportal
wait_for_url "$url/cbioportal/api/health" 300 || die "Portal failed after persistence restart"
curl -fsS "$url/cbioportal/api/studies/clamp_2026" | grep -q '"clamp_2026"' \
  || die "Study did not persist across restart"
log "Smoke tests passed"
