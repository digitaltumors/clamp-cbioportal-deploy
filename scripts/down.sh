#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_config
remove_volumes=false
confirmed=false
for arg in "$@"; do
  case "$arg" in
    --volumes) remove_volumes=true ;;
    --yes) confirmed=true ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

if [[ "$remove_volumes" == true ]]; then
  if [[ "$confirmed" != true ]]; then
    confirm "Delete the CLAMP MySQL and MongoDB volumes? This cannot be undone." \
      || die "Cancelled"
  fi
  compose down --volumes
  log "Stopped the stack and deleted its persistent volumes"
else
  compose down
  log "Stopped the stack; persistent volumes were retained"
fi
