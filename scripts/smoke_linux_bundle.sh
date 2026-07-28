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

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

set +e
timeout --signal=TERM 8s xvfb-run -a "$binary" >"$log_file" 2>&1
status=$?
set -e

if [[ "$status" -eq 0 || "$status" -eq 124 ]]; then
  exit 0
fi

cat "$log_file" >&2
echo "error: Linux bundle exited with status $status" >&2
exit "$status"
