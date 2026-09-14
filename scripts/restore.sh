#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
umask 077
require_config
backup_dir=""; confirmed=false
while (( $# > 0 )); do
  case "$1" in
    --backup) [[ -n "${2:-}" ]] || die "--backup requires a directory"; backup_dir="$(canonical_path "$2")"; shift 2 ;;
    --yes) confirmed=true; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done
[[ -n "$backup_dir" ]] || die "Usage: restore.sh --backup PATH [--yes]"
for file in manifest.env checksums.sha256; do [[ -f "$backup_dir/$file" ]] || die "Backup is missing $file"; done
(
  cd "$backup_dir"
  verify_sha256_manifest checksums.sha256
) || die "Backup checksum validation failed"
encrypted=false
if [[ -f "$backup_dir/mysql.sql.gz.age" && -f "$backup_dir/mongo.archive.gz.age" ]]; then
  encrypted=true
  require_command age
  identity="$(env_value BACKUP_AGE_IDENTITY)"
  [[ -n "$identity" && -f "$identity" ]] || die "Encrypted backup requires BACKUP_AGE_IDENTITY pointing to an age identity file"
elif [[ ! -f "$backup_dir/mysql.sql.gz" || ! -f "$backup_dir/mongo.archive.gz" ]]; then
  die "Backup database payloads are missing or use inconsistent encryption"
fi
if [[ "$confirmed" != true ]]; then
  confirm "Overwrite the current CLAMP MySQL and MongoDB contents from $backup_dir?" || die "Cancelled"
fi
compose stop web cbioportal cbioportal-session 2>/dev/null || true
compose --profile session up -d cbioportal-database cbioportal-session-database
log "Restoring MySQL"
if [[ "$encrypted" == true ]]; then
  # Credentials intentionally expand inside the database container.
  # shellcheck disable=SC2016
  age --decrypt --identity "$identity" "$backup_dir/mysql.sql.gz.age" | gzip -dc \
    | compose exec -T cbioportal-database sh -c 'exec mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"'
else
  # shellcheck disable=SC2016
  gzip -dc "$backup_dir/mysql.sql.gz" \
    | compose exec -T cbioportal-database sh -c 'exec mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"'
fi
log "Restoring MongoDB"
if [[ "$encrypted" == true ]]; then
  # Credentials intentionally expand inside the MongoDB container.
  # shellcheck disable=SC2016
  age --decrypt --identity "$identity" "$backup_dir/mongo.archive.gz.age" \
    | compose --profile session exec -T cbioportal-session-database sh -c \
      'exec mongorestore --host 127.0.0.1 --username "$MONGO_APP_USERNAME" --password "$MONGO_APP_PASSWORD" --authenticationDatabase session-service --drop --db session-service --archive --gzip'
else
  # shellcheck disable=SC2016
  compose --profile session exec -T cbioportal-session-database sh -c \
    'exec mongorestore --host 127.0.0.1 --username "$MONGO_APP_USERNAME" --password "$MONGO_APP_PASSWORD" --authenticationDatabase session-service --drop --db session-service --archive --gzip' \
    < "$backup_dir/mongo.archive.gz"
fi
"$ROOT_DIR/scripts/up.sh"
"$ROOT_DIR/scripts/smoke-test.sh"
log "Restore completed and passed smoke tests"
