#!/usr/bin/env bash
# Fail when a PowerShell/bash automation pair has drifted apart.
#
# The two platforms cannot share an implementation, so every invariant that
# keeps the app correct has to be written twice, and the copies drift. These
# are the ones that have already caused a bug: a refresh allowed to overlap
# itself, and a refresh pointed at the wrong database.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

failures=0

fail() {
  printf 'ops parity: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Scripts that run on a schedule -- or that can be started by hand while a
# scheduled run is in flight -- must refuse to overlap themselves on both
# platforms. Without this the two runs share tmp/tdx-update/hsjday.zip.part and
# corrupt each other's archive.
for name in daily-refresh ensure-public-preview; do
  grep -q 'flock' "bin/$name.sh" ||
    fail "bin/$name.sh takes no lock, so a second run can overlap the first"
  grep -q 'FileShare' "bin/$name.ps1" ||
    fail "bin/$name.ps1 takes no lock, so a second run can overlap the first"
done

# The nightly refresh has to default to the database config/database.yml uses.
# Pointing it at the isolated preview copy instead means the database the app
# serves from is never refreshed, and the status files keep reporting success.
grep -q 'db/stock\.sqlite3' bin/daily-refresh.sh ||
  fail "bin/daily-refresh.sh does not default to db/stock.sqlite3"
grep -q 'db\\stock\.sqlite3' bin/daily-refresh.ps1 ||
  fail "bin/daily-refresh.ps1 does not default to db/stock.sqlite3"
if grep -q 'tmp.ui-stock\.sqlite3' bin/daily-refresh.ps1; then
  fail "bin/daily-refresh.ps1 still defaults to the isolated preview database"
fi

# Every maintained script should exist on the other platform too. The
# daily-refresh installers are named for what each one installs -- a Scheduled
# Task, a cron entry, or a systemd timer -- so they are listed rather than
# paired, and this guard is a CI lint that only needs to run on Linux.
linux_only="check-ops-parity.sh install-daily-refresh-cron.sh install-daily-refresh-timer.sh"
windows_only="check-powershell-syntax.ps1 install-daily-refresh-task.ps1"

for script in bin/*.sh; do
  name="$(basename "$script")"
  case " $linux_only " in *" $name "*) continue ;; esac
  [[ -f "bin/${name%.sh}.ps1" ]] || fail "bin/$name has no PowerShell counterpart"
done

for script in bin/*.ps1; do
  name="$(basename "$script")"
  case " $windows_only " in *" $name "*) continue ;; esac
  [[ -f "bin/${name%.ps1}.sh" ]] || fail "bin/$name has no Linux counterpart"
done

if [[ "$failures" -gt 0 ]]; then
  printf 'ops parity: %s check(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'ops parity: every pair agrees\n'
