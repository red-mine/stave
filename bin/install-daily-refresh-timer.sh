#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_NAME="stave-daily-refresh"
USER_UNITS="$HOME/.config/systemd/user"

mkdir -p "$USER_UNITS"

install -m 644 "$REPO_DIR/extras/systemd/stave-daily-refresh.service" "$USER_UNITS/${SERVICE_NAME}.service"
install -m 644 "$REPO_DIR/extras/systemd/stave-daily-refresh.timer" "$USER_UNITS/${SERVICE_NAME}.timer"

# Replace placeholders with the actual repository path and user home.
sed -i "s|%h/work/stave|$REPO_DIR|g" "$USER_UNITS/${SERVICE_NAME}.service"
sed -i "s|%h|$HOME|g" "$USER_UNITS/${SERVICE_NAME}.service"

systemctl --user daemon-reload
systemctl --user enable --now "${SERVICE_NAME}.timer"

echo "Installed and started ${SERVICE_NAME}.timer"
echo "Status:"
systemctl --user status "${SERVICE_NAME}.timer" --no-pager

echo ""
echo "To check the next run time:"
echo "  systemctl --user list-timers ${SERVICE_NAME}.timer"
echo "To view logs:"
echo "  journalctl --user -u ${SERVICE_NAME}.service"
