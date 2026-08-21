#!/usr/bin/env bash
# Download, validate, and incrementally install the official TongdaXin day data.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_PATH="${TDX_DATA_PATH:-$REPO_ROOT/vipdoc}"
WORK_DIRECTORY="$REPO_ROOT/tmp/tdx-update"
METADATA_URI="https://data.tdx.com.cn/vipdoc/_hsjdayinfo.js"
ARCHIVE_URI="https://data.tdx.com.cn/vipdoc/hsjday.zip"
REUSE_ARCHIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-path) DATA_PATH="$2"; shift 2 ;;
    --work-directory) WORK_DIRECTORY="$2"; shift 2 ;;
    --metadata-uri) METADATA_URI="$2"; shift 2 ;;
    --archive-uri) ARCHIVE_URI="$2"; shift 2 ;;
    --reuse-archive) REUSE_ARCHIVE=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

for command_name in curl unzip python3 rsync od; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
done

DATA_PATH="$(realpath -m "$DATA_PATH")"
WORK_DIRECTORY="$(realpath -m "$WORK_DIRECTORY")"
ARCHIVE="$WORK_DIRECTORY/hsjday.zip"
PARTIAL_ARCHIVE="$WORK_DIRECTORY/hsjday.zip.part"
STAGING="$WORK_DIRECTORY/staging"

declare -A SAMPLES=(
  [sh]="sh000001.day"
  [sz]="sz399001.day"
  [bj]="bj920001.day"
)

last_record_date() {
  local path="$1" size encoded
  [[ -f "$path" ]] || return 0
  size="$(stat -c %s "$path")"
  if (( size < 32 || size % 32 != 0 )); then
    echo "Invalid TongdaXin day file: $path" >&2
    return 1
  fi
  encoded="$(od -An -t u4 -j "$((size - 32))" -N 4 "$path" | tr -d ' ')"
  if [[ ! "$encoded" =~ ^[0-9]{8}$ ]]; then
    echo "Invalid final TongdaXin date in: $path" >&2
    return 1
  fi
  printf '%s\n' "$encoded"
}

market_dates() {
  local root="$1" market value
  for market in bj sh sz; do
    value="$(last_record_date "$root/$market/lday/${SAMPLES[$market]}")"
    printf '%s=%s' "$market" "${value:-missing}"
    [[ "$market" == sz ]] || printf ', '
  done
  printf '\n'
}

cleanup_staging() {
  if [[ -d "$STAGING" ]]; then
    rm -rf -- "$STAGING"
  fi
}
trap cleanup_staging EXIT

mkdir -p "$WORK_DIRECTORY" "$DATA_PATH"
metadata_url="${METADATA_URI}$([[ "$METADATA_URI" == *\?* ]] && printf '&' || printf '?')t=$(date +%s)"
metadata="$(curl --fail --silent --show-error --location --connect-timeout 30 --max-time 60 \
  --retry 5 --retry-delay 5 --retry-max-time 120 --retry-all-errors "$metadata_url")"
remote_timestamp="$(printf '%s' "$metadata" | sed -n 's/.*HSJDAY_SOFT_TIME="\([^"]*\)".*/\1/p' | head -n 1)"
if [[ ! "$remote_timestamp" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
  echo "TongdaXin metadata did not contain a valid HSJDAY_SOFT_TIME" >&2
  exit 1
fi
remote_date="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"

echo "TongdaXin source: $(market_dates "$DATA_PATH"); official=${remote_date:0:4}-${remote_date:4:2}-${remote_date:6:2}"
needs_update=false
for market in bj sh sz; do
  current_date="$(last_record_date "$DATA_PATH/$market/lday/${SAMPLES[$market]}")"
  if [[ -z "$current_date" || "$current_date" < "$remote_date" ]]; then
    needs_update=true
  fi
done
if [[ "$needs_update" == false ]]; then
  echo "TongdaXin data is already current."
  exit 0
fi

if [[ "$REUSE_ARCHIVE" == true && -f "$ARCHIVE" ]]; then
  echo "Reusing previously downloaded archive: $ARCHIVE"
else
  if [[ ! -f "$PARTIAL_ARCHIVE" && -f "$ARCHIVE" ]] && ! unzip -tqq "$ARCHIVE" >/dev/null 2>&1; then
    echo "Recovering interrupted archive download: $ARCHIVE"
    mv -f -- "$ARCHIVE" "$PARTIAL_ARCHIVE"
  fi
  if [[ -f "$PARTIAL_ARCHIVE" ]]; then
    echo "Resuming official TongdaXin day archive at $(stat -c %s "$PARTIAL_ARCHIVE") bytes..."
  else
    echo "Downloading official TongdaXin day archive..."
  fi
  curl --fail --show-error --location --connect-timeout 30 --max-time 1800 \
    --retry 5 --retry-delay 5 --retry-max-time 1800 --retry-all-errors --continue-at - \
    --output "$PARTIAL_ARCHIVE" "$ARCHIVE_URI"
  if (( $(stat -c %s "$PARTIAL_ARCHIVE") < 1048576 )); then
    echo "Downloaded TongdaXin archive is unexpectedly small" >&2
    exit 1
  fi
  if ! unzip -tqq "$PARTIAL_ARCHIVE" >/dev/null; then
    echo "Downloaded TongdaXin archive failed its ZIP integrity check; removing the unusable partial file" >&2
    rm -f -- "$PARTIAL_ARCHIVE"
    exit 1
  fi
  mv -f -- "$PARTIAL_ARCHIVE" "$ARCHIVE"
fi
if (( $(stat -c %s "$ARCHIVE") < 1048576 )); then
  echo "Downloaded TongdaXin archive is unexpectedly small" >&2
  exit 1
fi

mapfile -t entries < <(unzip -Z1 "$ARCHIVE" | tr '\\' '/')
if (( ${#entries[@]} == 0 )); then
  echo "TongdaXin archive could not be read" >&2
  exit 1
fi
for entry in "${entries[@]}"; do
  if [[ "$entry" == /* || "$entry" =~ (^|/)\.\.(/|$) || "$entry" =~ ^[A-Za-z]: || ! "$entry" =~ ^(sh|sz|bj)/lday/ ]]; then
    echo "TongdaXin archive contains an unexpected path: $entry" >&2
    exit 1
  fi
done
declare -A archived_paths=()
for entry in "${entries[@]}"; do
  archived_paths["$entry"]=1
done
for market in bj sh sz; do
  expected="$market/lday/${SAMPLES[$market]}"
  if [[ -z "${archived_paths[$expected]:-}" ]]; then
    echo "TongdaXin archive is missing required sample: $expected" >&2
    exit 1
  fi
done

cleanup_staging
mkdir -p "$STAGING"
python3 - "$ARCHIVE" "$STAGING" <<'PY'
import pathlib
import shutil
import sys
import zipfile

archive_path = pathlib.Path(sys.argv[1])
staging = pathlib.Path(sys.argv[2]).resolve()
with zipfile.ZipFile(archive_path) as archive:
    for member in archive.infolist():
        normalized = member.filename.replace("\\", "/")
        relative = pathlib.PurePosixPath(normalized)
        if relative.is_absolute() or ".." in relative.parts:
            raise SystemExit(f"Unsafe archive member: {member.filename}")
        destination = staging.joinpath(*relative.parts)
        if member.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(member) as source, destination.open("wb") as output:
            shutil.copyfileobj(source, output)
PY
for market in bj sh sz; do
  staged_date="$(last_record_date "$STAGING/$market/lday/${SAMPLES[$market]}")"
  if [[ "$staged_date" != "$remote_date" ]]; then
    echo "TongdaXin $market sample date is ${staged_date:-missing}; expected $remote_date" >&2
    exit 1
  fi
done
echo "Verified archive dates: $(market_dates "$STAGING")"

for market in bj sh sz; do
  mkdir -p "$DATA_PATH/$market"
  rsync -a "$STAGING/$market/" "$DATA_PATH/$market/"
done
for market in bj sh sz; do
  final_date="$(last_record_date "$DATA_PATH/$market/lday/${SAMPLES[$market]}")"
  if [[ "$final_date" != "$remote_date" ]]; then
    echo "TongdaXin $market data failed final verification" >&2
    exit 1
  fi
done
echo "TongdaXin update complete: $(market_dates "$DATA_PATH")"
