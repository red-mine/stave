#!/usr/bin/env bash
# Check the managed preview twice, then restart its systemd service if needed.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RETRY_DELAY_SECONDS=15
RECOVERY_ATTEMPTS=30
RECOVERY_DELAY_SECONDS=5
MAXIMUM_LOG_BYTES=1048576
RETAINED_LOG_LINES=1000
RECOVER=true
LOG_DIR="$REPO_DIR/log/public-preview"
LOG_FILE="$LOG_DIR/monitor.log"
LOCK_FILE="$REPO_DIR/tmp/public-preview-monitor.lock"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --retry-delay) RETRY_DELAY_SECONDS="$2"; shift 2 ;;
    --recovery-attempts) RECOVERY_ATTEMPTS="$2"; shift 2 ;;
    --recovery-delay) RECOVERY_DELAY_SECONDS="$2"; shift 2 ;;
    --no-recover) RECOVER=false; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$LOG_DIR" "$REPO_DIR/tmp"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Public preview monitor is already running"
  exit 0
fi

if [[ -f "$LOG_FILE" ]] && (( $(stat -c %s "$LOG_FILE") > MAXIMUM_LOG_BYTES )); then
  tail -n "$(( RETAINED_LOG_LINES > 0 ? RETAINED_LOG_LINES : 1 ))" "$LOG_FILE" > "$LOG_FILE.tmp"
  mv -f "$LOG_FILE.tmp" "$LOG_FILE"
fi

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" | tee -a "$LOG_FILE"
}

check_health() {
  local report
  if report="$($REPO_DIR/bin/public-preview-status.sh 2>&1)"; then
    return 0
  fi
  log "Health details: ${report//$'\n'/; }"
  return 1
}

if check_health; then
  log "Preview healthy; no action needed."
  exit 0
fi

log "Preview health check failed; retrying in $RETRY_DELAY_SECONDS seconds."
sleep "$(( RETRY_DELAY_SECONDS > 0 ? RETRY_DELAY_SECONDS : 1 ))"
if check_health; then
  log "Preview recovered on retry; no restart needed."
  exit 0
fi

if [[ "$RECOVER" != true ]]; then
  log "Preview failed twice; recovery disabled by request."
  exit 1
fi

log "Preview failed twice; restarting stave-public-preview.service."
if ! systemctl --user restart stave-public-preview.service; then
  log "Preview recovery failed: systemd could not restart the service."
  exit 1
fi

for (( attempt = 1; attempt <= RECOVERY_ATTEMPTS; attempt++ )); do
  sleep "$(( RECOVERY_DELAY_SECONDS > 0 ? RECOVERY_DELAY_SECONDS : 1 ))"
  if check_health; then
    log "Preview recovery succeeded."
    exit 0
  fi
done

log "Preview recovery failed: health did not recover after $RECOVERY_ATTEMPTS checks."
exit 1
