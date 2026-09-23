#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
base_json="$(mktemp)"
auth_json="$(mktemp)"
trap 'rm -f "$base_json" "$auth_json"' EXIT
compose --profile '*' config --format json > "$base_json"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-security-test-only}" \
AUTH_TEST_PASSWORD="${AUTH_TEST_PASSWORD:-security-test-only}" \
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" --profile session \
  -f "$AUTH_COMPOSE_FILE" -f "$LOCAL_KEYCLOAK_COMPOSE_FILE" config --format json > "$auth_json"
python3 - "$base_json" "$auth_json" <<'PY'
import json
import pathlib
import sys
base = json.loads(pathlib.Path(sys.argv[1]).read_text())
auth = json.loads(pathlib.Path(sys.argv[2]).read_text())
services = base["services"]
port = services["web"]["ports"][0]
assert port["host_ip"] == "127.0.0.1" and port["target"] == 8080
assert set(services["web"]["networks"]) == {"portal-web"}
assert set(services["cbioportal-database"]["networks"]) == {"portal-database"}
assert set(services["cbioportal-session-database"]["networks"]) == {"session-database"}
for name in ("web", "cbioportal", "cbioportal-session", "study-loader"):
    service = services[name]
    assert service["read_only"] is True
    assert "ALL" in service["cap_drop"]
    assert "no-new-privileges" in service["security_opt"]
    assert int(service["pids_limit"]) > 0
    assert int(service["mem_limit"]) > 0
study_mount = next(m for m in services["study-loader"]["volumes"] if m["target"] == "/study/clamp_2026")
assert study_mount["type"] == "bind" and study_mount["read_only"] is True
assert study_mount["bind"]["selinux"] == "z"
portal_config = next(m for m in services["cbioportal"]["volumes"] if m["target"] == "/cbioportal-webapp/application.properties")
assert portal_config["bind"]["selinux"] == "z"
assert "@sha256:" in services["cbioportal-database"]["build"]["args"]["MYSQL_BASE"]
assert "@sha256:" in services["cbioportal-database"]["build"]["args"]["GOSU_BUILDER"]
assert "@sha256:" in services["cbioportal-session-database"]["build"]["args"]["MONGO_BASE"]
assert "@sha256:" in services["cbioportal-session-database"]["build"]["args"]["GOSU_BUILDER"]
assert "@sha256:" in services["cbioportal-session-database"]["build"]["args"]["NODE_BUILDER"]
assert "@sha256:" in services["cbioportal-session"]["build"]["args"]["MAVEN_BUILDER"]
assert "@sha256:" in services["cbioportal-session"]["build"]["args"]["JAVA_RUNTIME_BASE"]
assert len(services["cbioportal-session"]["build"]["args"]["SESSION_SERVICE_SOURCE_COMMIT"]) == 40
assert "@sha256:" in services["cbioportal"]["build"]["args"]["MAVEN_BUILDER"]
assert len(services["cbioportal"]["build"]["args"]["CBIOPORTAL_SOURCE_COMMIT"]) == 40
keycloak = auth["services"]["keycloak"]
assert keycloak["ports"][0]["host_ip"] == "127.0.0.1"
assert "@sha256:" in keycloak["build"]["args"]["KEYCLOAK_BASE"]
assert "@sha256:" in keycloak["build"]["args"]["MAVEN_BUILDER"]
assert "ALL" in keycloak["cap_drop"]
assert "no-new-privileges" in keycloak["security_opt"]
PY
grep -q '^studies$' "$ROOT_DIR/.dockerignore"
grep -q '^WEB_PORT=45000$' "$ROOT_DIR/.env.example"
grep -q '^KEYCLOAK_PORT=46000$' "$ROOT_DIR/.env.example"
grep -q '^DEV_MYSQL_PORT=47000$' "$ROOT_DIR/.env.example"
grep -q '^DEV_CBIOPORTAL_PORT=48000$' "$ROOT_DIR/.env.example"
if grep -q 'condition: service_healthy' "$ROOT_DIR"/compose*.yaml; then
  die "Compose health-conditioned dependencies are not portable to podman-compose"
fi
grep -q 'github.com/tianon/gosu@v0.0.0-20250923190938-6456aaa0f3c8' "$ROOT_DIR/database/mysql/Dockerfile"
grep -q 'github.com/tianon/gosu@v0.0.0-20250923190938-6456aaa0f3c8' "$ROOT_DIR/database/mongo/Dockerfile"
grep -Eq "default-src 'self'.*object-src 'none'.*frame-ancestors 'self'" \
  "$ROOT_DIR/web/portal-security-headers.conf"
if grep -Eiq '^COPY[[:space:]]+((--[^[:space:]]+)[[:space:]]+)*stud(y|ies)([/[:space:]]|$)' "$ROOT_DIR/study-loader/Dockerfile"; then
  die "Study data must not be copied into the loader image"
fi
grep -q '^cryptography==50\.0\.1 ' "$ROOT_DIR/cbioportal/security-requirements.txt"
grep -q -- '--require-hashes -r /tmp/security-requirements.txt' "$ROOT_DIR/cbioportal/Dockerfile"
grep -q '^ARG CBIOPORTAL_BASE=docker.io/' "$ROOT_DIR/cbioportal/Dockerfile"
grep -q '^ARG CBIOPORTAL_BASE=clamp-cbioportal:local' "$ROOT_DIR/study-loader/Dockerfile"
grep -q 'git apply --check /tmp/security-dependencies.patch' "$ROOT_DIR/cbioportal/Dockerfile"
grep -q 'org.cbioportal.PortalApplication' "$ROOT_DIR/cbioportal/Dockerfile"
grep -q '^ENTRYPOINT \[\]$' "$ROOT_DIR/cbioportal/Dockerfile"
grep -q 'git apply --check /tmp/security-dependencies.patch' "$ROOT_DIR/session-service/Dockerfile"
grep -q 'js-yaml@3.15.2' "$ROOT_DIR/database/mongo/Dockerfile"
grep -q 'netty-handler-4.1.137.Final.jar' "$ROOT_DIR/auth/keycloak/Dockerfile"
grep -q 'bcprov-jdk18on-1.85.jar' "$ROOT_DIR/auth/keycloak/Dockerfile"
grep -q 'empty-mssql-driver.jar' "$ROOT_DIR/auth/keycloak/Dockerfile"
grep -q '^ARG MYSQL_BASE=docker.io/' "$ROOT_DIR/database/mysql/Dockerfile"
"$ROOT_DIR/scripts/validate-trivy-exceptions.py" --self-test
"$ROOT_DIR/scripts/validate-trivy-exceptions.py" "$ROOT_DIR/.trivyignore.yaml"
grep -q -- "--ignorefile \"\$exception_policy\" --show-suppressed" \
  "$ROOT_DIR/scripts/scan-images.sh"
grep -q -- '--ignorefile /policy/.trivyignore.yaml --show-suppressed' \
  "$ROOT_DIR/scripts/scan-images.sh"
grep -q 'trivy.baseline.json' "$ROOT_DIR/scripts/scan-images.sh"
log "Effective Compose and build-context security assertions passed"
