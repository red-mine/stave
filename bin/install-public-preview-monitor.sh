#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_UNITS="$HOME/.config/systemd/user"
UNITS=(
  stave-public-preview.service
  stave-public-preview-monitor.service
  stave-public-preview-monitor.timer
)

mkdir -p "$USER_UNITS"
for unit in "${UNITS[@]}"; do
  install -m 644 "$REPO_DIR/extras/systemd/$unit" "$USER_UNITS/$unit"
  sed -i "s|%h/work/stave|$REPO_DIR|g" "$USER_UNITS/$unit"
  sed -i "s|%h|$HOME|g" "$USER_UNITS/$unit"
done

systemctl --user daemon-reload
systemctl --user enable --now stave-public-preview.service
systemctl --user enable --now stave-public-preview-monitor.timer

echo "Installed the managed preview and 30-minute health monitor."
echo "Status: systemctl --user status stave-public-preview.service stave-public-preview-monitor.timer"
echo "Logs:   journalctl --user -u stave-public-preview.service -u stave-public-preview-monitor.service"
