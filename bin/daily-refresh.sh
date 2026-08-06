#!/usr/bin/env bash
# Linux equivalent of bin/daily-refresh.ps1: runs `rails daily_refresh` with
# logging, log rotation, and the same STOCK_DATABASE/STOCK_REFRESH_SOURCE
# environment contract the Rake task and RefreshRun status files expect.
set -euo pipefail

DATABASE_PATH=""
RUN_SOURCE="manual"
LOG_RETENTION=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --database) DATABASE_PATH="$2"; shift 2 ;;
    --source)
      case "$2" in
        manual|scheduled) RUN_SOURCE="$2" ;;
        *) echo "Invalid --source '$2'; expected manual or scheduled" >&2; exit 1 ;;
      esac
      shift 2 ;;
    --log-retention) LOG_RETENTION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATABASE_PATH="${DATABASE_PATH:-$REPO_ROOT/db/stock.sqlite3}"
LOG_DIR="$REPO_ROOT/log/daily-refresh"
LOG_FILE="$LOG_DIR/latest.log"
ARCHIVE_LOG="$LOG_DIR/refresh-$(date -u +%Y%m%d-%H%M%S)-$$.log"

resolve_ruby() {
  if [[ -n "${RUBY_BIN:-}" ]]; then
    echo "$RUBY_BIN"
  elif command -v ruby >/dev/null 2>&1; then
    command -v ruby
  elif [[ -x "$HOME/.rbenv/shims/ruby" ]]; then
    echo "$HOME/.rbenv/shims/ruby"
  else
    echo ""
  fi
}

RUBY_BIN="$(resolve_ruby)"
if [[ -z "$RUBY_BIN" || ! -x "$RUBY_BIN" ]]; then
  echo "Ruby executable not found (set RUBY_BIN to override)" >&2
  exit 1
fi
if [[ ! -f "$DATABASE_PATH" ]]; then
  echo "Stock database not found: $DATABASE_PATH" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
export STOCK_DATABASE="$DATABASE_PATH"
export STOCK_REFRESH_SOURCE="$RUN_SOURCE"
export RAILS_ENV="development"
export RACK_ENV="development"

cd "$REPO_ROOT"

: > "$LOG_FILE"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting daily refresh" | tee -a "$LOG_FILE"

set +e
"$RUBY_BIN" bin/rails daily_refresh 2>&1 | tee -a "$LOG_FILE"
status="${PIPESTATUS[0]}"
set -e

if [[ "$status" -eq 0 ]]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Daily refresh succeeded" | tee -a "$LOG_FILE"
else
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Daily refresh failed with exit code $status" | tee -a "$LOG_FILE"
fi

cp "$LOG_FILE" "$ARCHIVE_LOG"

keep=$(( LOG_RETENTION > 1 ? LOG_RETENTION : 1 ))
# shellcheck disable=SC2012
ls -1t "$LOG_DIR"/refresh-*.log 2>/dev/null | tail -n +$((keep + 1)) | xargs -r rm -f

exit "$status"
