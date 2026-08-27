#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
destination="$ROOT_DIR/backups"
if [[ "${1:-}" == "--destination" ]]; then
  [[ -n "${2:-}" ]] || die "--destination requires a path"
  destination="$(realpath -m "$2")"
elif (( $# > 0 )); then
  die "Usage: backup.sh [--destination PATH]"
fi

mkdir -p "$destination"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="$destination/$timestamp"
[[ ! -e "$backup_dir" ]] || die "Backup already exists: $backup_dir"
mkdir -p "$backup_dir"

compose up -d cbioportal-database cbioportal-session-database
log "Creating MySQL logical backup"
compose exec -T cbioportal-database sh -c \
  'exec mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --single-transaction --no-tablespaces --routines --triggers --add-drop-table "$MYSQL_DATABASE"' \
  | gzip -9 > "$backup_dir/mysql.sql.gz"

log "Creating MongoDB logical backup"
compose exec -T cbioportal-session-database mongodump \
  --db session-service --archive --gzip > "$backup_dir/mongo.archive.gz"

{
  printf 'BACKUP_CREATED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'COMPOSE_PROJECT_NAME=%s\n' "$(project_name)"
  printf 'IMAGE_REVISION=%s\n' "$(image_revision)"
  printf 'STUDY_VERSION=%s\n' "$(study_hash)"
  if [[ -f "$ROOT_DIR/reports/last-import.env" ]]; then
    sed 's/^/IMPORTED_/' "$ROOT_DIR/reports/last-import.env"
  fi
} > "$backup_dir/manifest.env"

(
  cd "$backup_dir"
  sha256sum mysql.sql.gz mongo.archive.gz manifest.env > checksums.sha256
)
log "Backup created at $backup_dir"
