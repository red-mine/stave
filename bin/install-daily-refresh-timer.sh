#!/usr/bin/env bash
set -e

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

echo "Installed and started timers:"
systemctl --user status stave-daily-refresh.timer stave-retention.timer --no-pager

echo ""
echo "To check the next run time:"
echo "  systemctl --user list-timers stave-daily-refresh.timer stave-retention.timer"
echo "To view logs:"
echo "  journalctl --user -u stave-daily-refresh.service"
echo "  journalctl --user -u stave-retention.service"
