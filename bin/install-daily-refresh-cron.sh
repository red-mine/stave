#!/usr/bin/env bash
# Linux equivalent of bin/install-daily-refresh-task.ps1: installs (or
# replaces) a per-user cron entry that runs bin/daily-refresh.sh nightly, and
# records the schedule in tmp/stock-refresh-schedule.json so the web UI can
# report it via Stock::RefreshSchedule the same way it does on Windows.
set -euo pipefail

echo "Warning: cron installation is deprecated; prefer bin/install-daily-refresh-timer.sh." >&2

AT="20:30"
TASK_NAME="Stock Stave Daily Refresh"
MARKER="# stock-stave-daily-refresh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --at) AT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ ! "$AT" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  echo "Invalid --at '$AT'; expected 24-hour HH:mm" >&2
  exit 1
fi
HOUR="${AT%%:*}"; HOUR="${HOUR#0}"; HOUR="${HOUR:-0}"
MINUTE="${AT##*:}"; MINUTE="${MINUTE#0}"; MINUTE="${MINUTE:-0}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/bin/daily-refresh.sh"
STATUS_PATH="$REPO_ROOT/tmp/stock-refresh-schedule.json"

if [[ ! -x "$RUNNER" ]]; then
  echo "Runner not found or not executable: $RUNNER" >&2
  exit 1
fi

CRON_LINE="$MINUTE $HOUR * * * cd $REPO_ROOT && \"$RUNNER\" --source scheduled >/dev/null 2>&1 $MARKER"

EXISTING="$(crontab -l 2>/dev/null || true)"
FILTERED="$(printf '%s\n' "$EXISTING" | grep -vF "$MARKER" || true)"
printf '%s\n%s\n' "$FILTERED" "$CRON_LINE" | sed '/^$/d' | crontab -

mkdir -p "$REPO_ROOT/tmp"
INSTALLED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$STATUS_PATH" <<JSON
{
  "task_name": "$TASK_NAME",
  "time": "$AT",
  "enabled": true,
  "installed_at": "$INSTALLED_AT"
}
JSON

echo "Installed cron entry:"
crontab -l | grep -F "$MARKER"
