#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_UNITS="$HOME/.config/systemd/user"

install_service() {
  local name="$1"
  install -m 644 "$REPO_DIR/extras/systemd/${name}.service" "$USER_UNITS/${name}.service"
  install -m 644 "$REPO_DIR/extras/systemd/${name}.timer" "$USER_UNITS/${name}.timer"
  sed -i "s|%h/work/stave|$REPO_DIR|g" "$USER_UNITS/${name}.service"
  sed -i "s|%h|$HOME|g" "$USER_UNITS/${name}.service"
}

mkdir -p "$USER_UNITS"

install_service "stave-daily-refresh"
install_service "stave-retention"

systemctl --user daemon-reload
systemctl --user enable --now stave-daily-refresh.timer
systemctl --user enable --now stave-retention.timer

# A cron entry from the deprecated installer would fire the same runner seconds
# after the timer does, and two concurrent runs corrupt the shared download in
# tmp/tdx-update. The timer owns the schedule now, so drop the cron entry.
if crontab -l 2>/dev/null | grep -q 'daily-refresh\.sh'; then
  # `grep -v` exits 1 when the conflicting entry is the only line in the
  # crontab, which would abort the script under `set -o pipefail`; tolerate that
  # the same way bin/install-daily-refresh-cron.sh does.
  crontab -l 2>/dev/null | { grep -v 'daily-refresh\.sh' || true; } | crontab -
  echo "Removed a conflicting daily-refresh.sh cron entry; the systemd timer now owns the schedule."
fi

mkdir -p "$REPO_DIR/tmp"
installed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$REPO_DIR/tmp/stock-refresh-schedule.json" <<JSON
{
  "task_name": "Stock Stave Daily Refresh (systemd)",
  "time": "20:30",
  "enabled": true,
  "installed_at": "$installed_at"
}
JSON

echo "Installed and started timers:"
systemctl --user status stave-daily-refresh.timer stave-retention.timer --no-pager

echo ""
echo "To check the next run time:"
echo "  systemctl --user list-timers stave-daily-refresh.timer stave-retention.timer"
echo "To view logs:"
echo "  journalctl --user -u stave-daily-refresh.service"
echo "  journalctl --user -u stave-retention.service"
