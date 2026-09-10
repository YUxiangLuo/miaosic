#!/usr/bin/env bash
# Run a bundle built with --target tool/font_probe.dart. Unlike the regular
# startup smoke check, a timeout or an unrelated app entry point must fail.
set -euo pipefail

binary="${1:-build/linux/x64/release/bundle/miaosic}"
probe_dir="$(mktemp -d)"
trap 'rm -rf "$probe_dir"' EXIT

if ! timeout --signal=TERM 20s xvfb-run -a env \
  GDK_BACKEND=x11 \
  XDG_DATA_HOME="$probe_dir/data" \
  XDG_CONFIG_HOME="$probe_dir/config" \
  XDG_CACHE_HOME="$probe_dir/cache" \
  "$binary" >"$probe_dir/run.log" 2>&1; then
  cat "$probe_dir/run.log" >&2
  exit 1
fi

while IFS= read -r line; do
  if [[ "$line" == FONT_PROBE_OK:* ]]; then
    echo "$line"
    exit 0
  fi
done <"$probe_dir/run.log"
cat "$probe_dir/run.log" >&2
echo "error: The bundle did not complete the Chinese font probe" >&2
exit 1
