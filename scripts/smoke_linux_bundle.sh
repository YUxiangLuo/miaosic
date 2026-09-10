#!/usr/bin/env bash
set -euo pipefail

bundle_dir="${1:-build/linux/x64/release/bundle}"
binary="$bundle_dir/miaosic"

if [[ ! -x "$binary" ]]; then
  echo "error: Linux bundle executable not found: $binary" >&2
  exit 1
fi
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "error: xvfb-run is required for the Linux bundle smoke test" >&2
  exit 1
fi

smoke_dir="$(mktemp -d)"
log_file="$smoke_dir/run.log"
trap 'rm -rf "$smoke_dir"' EXIT

set +e
timeout --signal=TERM 8s xvfb-run -a env \
  GDK_BACKEND=x11 \
  XDG_DATA_HOME="$smoke_dir/data" \
  XDG_CONFIG_HOME="$smoke_dir/config" \
  XDG_CACHE_HOME="$smoke_dir/cache" \
  "$binary" >"$log_file" 2>&1
status=$?
set -e

if [[ "$status" -eq 0 || "$status" -eq 124 ]]; then
  exit 0
fi

cat "$log_file" >&2
echo "error: Linux bundle exited with status $status" >&2
exit "$status"
