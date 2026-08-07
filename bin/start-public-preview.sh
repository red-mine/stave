#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

PORT="${STOCK_PREVIEW_PORT:-3000}"
DATABASE="${STOCK_DATABASE:-$REPO_DIR/tmp/ui-stock.sqlite3}"
ISOLATED_DATABASE="$REPO_DIR/tmp/ui-stock.sqlite3"
STATUS_PATH="$REPO_DIR/tmp/public-preview.json"
LOCK_PATH="$REPO_DIR/tmp/public-preview-start.lock"
TUNNEL_OUT="$REPO_DIR/tmp/cloudflared-out.log"
TUNNEL_ERR="$REPO_DIR/tmp/cloudflared-err.log"
SERVER_OUT="$REPO_DIR/tmp/public-preview-server-out.log"
SERVER_ERR="$REPO_DIR/tmp/public-preview-server-err.log"
CLOUDFLARED="${CLOUDFLARED:-cloudflared}"
AREAS=(sz sh bj)

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -n "${TUNNEL_PID:-}" ]]; then
    kill "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
  rm -f "$LOCK_PATH"
}

trap cleanup EXIT

acquire_lock() {
  if ! mkdir "$LOCK_PATH" 2>/dev/null; then
    if [[ "$(find "$LOCK_PATH" -mmin +5 2>/dev/null)" ]]; then
      rmdir "$LOCK_PATH" 2>/dev/null || true
      mkdir "$LOCK_PATH" 2>/dev/null || {
        echo "A public preview start is already running" >&2
        exit 1
      }
    else
      echo "A public preview start is already running" >&2
      exit 1
    fi
  fi
}

acquire_lock

if [[ "$DATABASE" != "$ISOLATED_DATABASE" ]]; then
  echo "Public preview must use the isolated database: $ISOLATED_DATABASE" >&2
  exit 1
fi

if ! command -v "$CLOUDFLARED" >/dev/null 2>&1; then
  echo "cloudflared not found. Install it first:" >&2
  echo "  https://github.com/cloudflare/cloudflared#installing-cloudflared" >&2
  exit 1
fi

if [[ ! -f "$DATABASE" ]]; then
  echo "Isolated database not found: $DATABASE" >&2
  echo "Run: STOCK_DATABASE=$DATABASE bundle exec rails db:prepare" >&2
  exit 1
fi

# Stop any existing Rails server on the same port.
pids=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
if [[ -n "$pids" ]]; then
  echo "Stopping existing Rails server on port $PORT"
  kill "$pids" 2>/dev/null || true
  sleep 2
fi

# Stop any existing cloudflared tunnel.
existing_tunnel=$(pgrep -f "cloudflared.*tunnel.*127.0.0.1:$PORT" || true)
if [[ -n "$existing_tunnel" ]]; then
  kill "$existing_tunnel" 2>/dev/null || true
  sleep 1
fi

rm -f "$TUNNEL_OUT" "$TUNNEL_ERR" "$SERVER_OUT" "$SERVER_ERR"

export STOCK_DATABASE="$DATABASE"
export RAILS_ENV="development"
export RACK_ENV="development"
export RAILS_LOG_LEVEL="warn"
export PUBLIC_PREVIEW="1"
export ASSET_CACHE_PATH="memory"

# Start cloudflared tunnel.
"$CLOUDFLARED" tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" --http-host-header localhost \
  >"$TUNNEL_OUT" 2>"$TUNNEL_ERR" &
TUNNEL_PID=$!

PUBLIC_URL=""
for _ in $(seq 1 30); do
  PUBLIC_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_OUT" 2>/dev/null | head -1 || true)
  if [[ -n "$PUBLIC_URL" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$PUBLIC_URL" ]]; then
  echo "Cloudflare did not issue a public URL within 60 seconds" >&2
  exit 1
fi

export PUBLIC_TUNNEL_HOST="${PUBLIC_URL#https://}"

# Start Rails server.
bundle exec rails server -p "$PORT" -b 127.0.0.1 >"$SERVER_OUT" 2>"$SERVER_ERR" &
SERVER_PID=$!

# Wait for Rails to listen.
for _ in $(seq 1 40); do
  if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
    break
  fi
  sleep 3
done

if ! lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
  echo "Rails did not listen on port $PORT within 120 seconds" >&2
  exit 1
fi

# Health checks.
health_ok() {
  local url="$1"
  local body
  body=$(curl -fsS --max-time 15 "$url/preview-health" 2>/dev/null) || return 1
  [[ "$body" == *'"status":"ready"'* ]] && [[ "$body" == *'"environment":"development"'* ]]
}

markets_ok() {
  local base="$1"
  for area in "${AREAS[@]}"; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$base/$area" 2>/dev/null || echo 0)
    if [[ "$code" != "200" ]]; then
      echo "$area=$code"
      return 1
    fi
  done
}

HEALTHY=false
for _ in $(seq 1 18); do
  if health_ok "http://127.0.0.1:$PORT" && health_ok "$PUBLIC_URL" && \
     markets_ok "http://127.0.0.1:$PORT" && markets_ok "$PUBLIC_URL"; then
    HEALTHY=true
    break
  fi
  sleep 5
done

if [[ "$HEALTHY" != "true" ]]; then
  echo "Preview market health check failed" >&2
  exit 1
fi

# Write status file.
RAILS_PID=$(lsof -ti tcp:"$PORT" | head -1)
cat >"$STATUS_PATH" <<EOF
{
  "url": "$PUBLIC_URL",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "rails_pid": $RAILS_PID,
  "tunnel_pid": $TUNNEL_PID,
  "database": "$DATABASE",
  "port": $PORT,
  "environment": "development",
  "log_level": "warn"
}
EOF

echo "Public preview running at $PUBLIC_URL"
echo "Local: http://127.0.0.1:$PORT"
echo "Status: $STATUS_PATH"

# Keep running until interrupted.
wait "$SERVER_PID"
