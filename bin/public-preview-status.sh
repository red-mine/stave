#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATUS_PATH="${1:-$REPO_DIR/tmp/public-preview.json}"
AREAS=(sz sh bj)

if [[ ! -f "$STATUS_PATH" ]]; then
  echo "Preview status not found: $STATUS_PATH" >&2
  exit 1
fi

read_json() {
  ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))[ARGV[1]]' "$STATUS_PATH" "$1"
}

PUBLIC_URL=$(read_json url)
PORT=$(read_json port)
RAILS_PID=$(read_json rails_pid)
TUNNEL_PID=$(read_json tunnel_pid)
DATABASE=$(read_json database)

is_running() {
  local pid="$1" expected="$2" executable
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  executable="$(basename "$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)" 2>/dev/null || true)"
  [[ "$executable" == "$expected"* ]]
}

health_report() {
  local url="$1"
  local response code body
  # No -f: the endpoint answers 503 when the preview data is incomplete, and
  # the report should say so rather than collapse it into "unavailable".
  response=$(curl -sS --max-time 15 -w $'\n%{http_code}' "$url/preview-health" 2>/dev/null) ||
    { echo "0/unavailable"; return; }
  code="${response##*$'\n'}"
  body="${response%$'\n'*}"
  local ready="incomplete"
  if [[ "$code" == "200" ]] && \
     echo "$body" | grep -q '"status":"ready"' && \
     echo "$body" | grep -q '"environment":"production"' && \
     echo "$body" | grep -q '"log_level":"warn"'; then
    ready="ready"
  fi
  echo "$code/$ready"
}

market_codes() {
  local base="$1"
  local out=""
  for area in "${AREAS[@]}"; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$base/$area" 2>/dev/null || echo 0)
    out="$out $area=$code"
  done
  echo "$out"
}

LOCAL_HEALTH=$(health_report "http://127.0.0.1:$PORT")
PUBLIC_HEALTH=$(health_report "$PUBLIC_URL")
LOCAL_MARKETS=$(market_codes "http://127.0.0.1:$PORT")
PUBLIC_MARKETS=$(market_codes "$PUBLIC_URL")

RAILS_RUNNING="false"
TUNNEL_RUNNING="false"
DATABASE_ISOLATED="false"
if is_running "$RAILS_PID" ruby; then
  RAILS_RUNNING="true"
fi
if is_running "$TUNNEL_PID" cloudflared; then
  TUNNEL_RUNNING="true"
fi
[[ "$DATABASE" == "$REPO_DIR/tmp/ui-stock.sqlite3" ]] && DATABASE_ISOLATED="true"

markets_ready() {
  local report="$1" area
  for area in "${AREAS[@]}"; do
    [[ "$report" == *" $area=200"* ]] || return 1
  done
}

HEALTHY="false"
if [[ "$RAILS_RUNNING" == "true" && "$TUNNEL_RUNNING" == "true" && \
      "$DATABASE_ISOLATED" == "true" && \
      "$LOCAL_HEALTH" == "200/ready" && "$PUBLIC_HEALTH" == "200/ready" ]]; then
  if markets_ready "$LOCAL_MARKETS" && markets_ready "$PUBLIC_MARKETS"; then
    HEALTHY="true"
  fi
fi

cat <<EOF
Url:            $PUBLIC_URL
Port:           $PORT
RailsPid:       $RAILS_PID ($RAILS_RUNNING)
TunnelPid:      $TUNNEL_PID ($TUNNEL_RUNNING)
Database:       $DATABASE (isolated=$DATABASE_ISOLATED)
LocalHealth:    $LOCAL_HEALTH
PublicHealth:   $PUBLIC_HEALTH
LocalMarkets:   $LOCAL_MARKETS
PublicMarkets:  $PUBLIC_MARKETS
Healthy:        $HEALTHY
EOF

if [[ "$HEALTHY" != "true" ]]; then
  exit 1
fi
