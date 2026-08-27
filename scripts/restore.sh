#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
backup_dir=""
confirmed=false
while (( $# > 0 )); do
  case "$1" in
    --backup)
      [[ -n "${2:-}" ]] || die "--backup requires a directory"
      backup_dir="$(realpath "$2")"
      shift 2
      ;;
    --yes)
      confirmed=true
      shift
      ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$backup_dir" ]] || die "Usage: restore.sh --backup PATH [--yes]"
for file in mysql.sql.gz mongo.archive.gz manifest.env checksums.sha256; do
  [[ -f "$backup_dir/$file" ]] || die "Backup is missing $file"
done
(
  cd "$backup_dir"
  sha256sum -c checksums.sha256
) || die "Backup checksum validation failed"

if [[ "$confirmed" != true ]]; then
  confirm "Overwrite the current CLAMP MySQL and MongoDB contents from $backup_dir?" \
    || die "Cancelled"
fi

compose stop web cbioportal cbioportal-session 2>/dev/null || true
compose up -d cbioportal-database cbioportal-session-database
log "Restoring MySQL"
gzip -dc "$backup_dir/mysql.sql.gz" \
  | compose exec -T cbioportal-database sh -c \
      'exec mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"'
log "Restoring MongoDB"
compose exec -T cbioportal-session-database mongorestore \
  --drop --db session-service --archive --gzip < "$backup_dir/mongo.archive.gz"

"$ROOT_DIR/scripts/up.sh"
"$ROOT_DIR/scripts/smoke-test.sh"
log "Restore completed and passed smoke tests"
