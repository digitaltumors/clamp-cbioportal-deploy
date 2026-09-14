#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
umask 077
confirmed=false
[[ "${1:-}" == "--yes" ]] && confirmed=true
(( $# <= 1 )) || die "Usage: migrate-mongo-4.2.sh [--yes]"
require_config
require_command docker
project="$(project_name)"
database_container="$(docker ps -a --filter "label=com.docker.compose.project=$project" \
  --filter 'label=com.docker.compose.service=cbioportal-session-database' --format '{{.ID}}')"
[[ -n "$database_container" && "$database_container" != *$'\n'* ]] \
  || die "Expected exactly one legacy session database container for project $project"
version="$(docker inspect --format '{{.Config.Image}}' "$database_container")"
[[ "$version" == mongo:4.2* ]] || die "Expected a MongoDB 4.2 container, found $version"
volume="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data/db"}}{{.Name}}{{end}}{{end}}' "$database_container")"
[[ -n "$volume" ]] || die "Could not resolve the exact legacy MongoDB data volume"
if [[ "$confirmed" != true ]]; then
  confirm "Migrate $volume from MongoDB 4.2 to the pinned MongoDB 7 image? A logical rollback dump will be retained." || die "Cancelled"
fi
mkdir -p "$ROOT_DIR/backups"; chmod 0700 "$ROOT_DIR/backups"
backup_dir="$ROOT_DIR/backups/mongo-4.2-migration-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$backup_dir"; chmod 0700 "$backup_dir"
was_running="$(docker inspect --format '{{.State.Running}}' "$database_container")"
[[ "$was_running" == true ]] || docker start "$database_container" >/dev/null
log "Creating MongoDB 4.2 logical rollback archive"
docker exec "$database_container" mongodump --host 127.0.0.1 --db session-service --archive --gzip \
  > "$backup_dir/mongo.archive.gz"
chmod 0600 "$backup_dir/mongo.archive.gz"
( cd "$backup_dir" && sha256_files mongo.archive.gz > checksums.sha256 )
chmod 0600 "$backup_dir/checksums.sha256"
docker ps -a --filter "label=com.docker.compose.project=$project" \
  --filter 'label=com.docker.compose.service=cbioportal-session' --format '{{.ID}}' \
  | while IFS= read -r container; do
      [[ -n "$container" ]] && docker rm -f "$container" >/dev/null
    done
docker rm -f "$database_container" >/dev/null
docker volume rm "$volume" >/dev/null
compose --profile session up -d --wait --wait-timeout 120 cbioportal-session-database
log "Restoring the logical archive into authenticated MongoDB 7"
# Credentials intentionally expand inside the MongoDB container.
# shellcheck disable=SC2016
compose --profile session exec -T cbioportal-session-database sh -c \
  'exec mongorestore --host 127.0.0.1 --username "$MONGO_APP_USERNAME" --password "$MONGO_APP_PASSWORD" --authenticationDatabase session-service --db session-service --archive --gzip' \
  < "$backup_dir/mongo.archive.gz"
compose --profile session up -d cbioportal-session
log "Migration complete; rollback archive retained at $backup_dir"
