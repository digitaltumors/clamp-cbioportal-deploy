#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

umask 077

require_config
destination="$ROOT_DIR/backups"
if [[ "${1:-}" == "--destination" ]]; then
  [[ -n "${2:-}" ]] || die "--destination requires a path"
  destination="$(canonical_path "$2")"
elif (( $# > 0 )); then
  die "Usage: backup.sh [--destination PATH]"
fi

mkdir -p "$destination"
chmod 0700 "$destination"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="$destination/$timestamp"
[[ ! -e "$backup_dir" ]] || die "Backup already exists: $backup_dir"
mkdir -p "$backup_dir"
chmod 0700 "$backup_dir"

compose --profile session up -d cbioportal-database cbioportal-session-database
log "Creating MySQL logical backup"
# Variables below intentionally expand inside the database container.
# shellcheck disable=SC2016
compose exec -T cbioportal-database sh -c \
  'exec mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --single-transaction --no-tablespaces --routines --triggers --add-drop-table "$MYSQL_DATABASE"' \
  | gzip -9 > "$backup_dir/mysql.sql.gz"

log "Creating MongoDB logical backup"
# Credentials intentionally expand inside the MongoDB container.
# shellcheck disable=SC2016
compose --profile session exec -T cbioportal-session-database sh -c \
  'exec mongodump --host 127.0.0.1 --username "$MONGO_APP_USERNAME" --password "$MONGO_APP_PASSWORD" --authenticationDatabase session-service --db session-service --archive --gzip' \
  > "$backup_dir/mongo.archive.gz"

encrypted=false
recipient="$(env_value BACKUP_AGE_RECIPIENT)"
if [[ -n "$recipient" ]]; then
  require_command age
  log "Encrypting database backup payloads with age"
  for file in mysql.sql.gz mongo.archive.gz; do
    age --recipient "$recipient" --output "$backup_dir/$file.age" "$backup_dir/$file"
    chmod 0600 "$backup_dir/$file.age"
    rm -f "$backup_dir/$file"
  done
  encrypted=true
fi

{
  printf 'BACKUP_CREATED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'BACKUP_ENCRYPTED=%s\n' "$encrypted"
  printf 'COMPOSE_PROJECT_NAME=%s\n' "$(project_name)"
  printf 'IMAGE_REVISION=%s\n' "$(image_revision)"
  printf 'STUDY_VERSION=%s\n' "$(study_hash)"
  if [[ -f "$ROOT_DIR/reports/last-import.env" ]]; then
    sed 's/^/IMPORTED_/' "$ROOT_DIR/reports/last-import.env"
  fi
} > "$backup_dir/manifest.env"

(
  cd "$backup_dir"
  if [[ "$encrypted" == true ]]; then
    sha256_files mysql.sql.gz.age mongo.archive.gz.age manifest.env > checksums.sha256
  else
    sha256_files mysql.sql.gz mongo.archive.gz manifest.env > checksums.sha256
  fi
)
chmod 0600 "$backup_dir"/*
log "Backup created at $backup_dir"
