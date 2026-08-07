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
  ruby -rjson -e "puts JSON.parse(File.read('$STATUS_PATH'))['$1']"
}

PUBLIC_URL=$(read_json url)
PORT=$(read_json port)
RAILS_PID=$(read_json rails_pid)
TUNNEL_PID=$(read_json tunnel_pid)
DATABASE=$(read_json database)

is_running() {
  kill -0 "$1" 2>/dev/null
}

health_report() {
  local url="$1"
  local body
  body=$(curl -fsS --max-time 15 "$url/preview-health" 2>/dev/null) || { echo "0/unavailable"; return; }
  local code=200
  local ready="incomplete"
  if echo "$body" | grep -q '"status":"ready"' && \
     echo "$body" | grep -q '"environment":"development"' && \
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
[[ -d "/proc/$RAILS_PID" ]] && RAILS_RUNNING="true"
[[ -d "/proc/$TUNNEL_PID" ]] && TUNNEL_RUNNING="true"
[[ "$DATABASE" == "$REPO_DIR/tmp/ui-stock.sqlite3" ]] && DATABASE_ISOLATED="true"

HEALTHY="false"
if [[ "$RAILS_RUNNING" == "true" && "$TUNNEL_RUNNING" == "true" && \
      "$DATABASE_ISOLATED" == "true" && \
      "$LOCAL_HEALTH" == "200/ready" && "$PUBLIC_HEALTH" == "200/ready" ]]; then
  HEALTHY="true"
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
