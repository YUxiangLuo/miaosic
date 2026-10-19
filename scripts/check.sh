#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

check_linux=false
clean_linux=false
for option in "$@"; do
  case "$option" in
    --linux) check_linux=true ;;
    --clean) clean_linux=true ;;
    -h|--help)
      echo 'Usage: scripts/check.sh [--linux] [--clean]'
      echo 'Run source checks and tests; --linux also builds and checks the Linux bundle.'
      echo '--clean resets the Linux build directory before the bundle checks.'
      exit 0
      ;;
    *) echo "error: unknown option: $option" >&2; exit 1 ;;
  esac
done
if $clean_linux && ! $check_linux; then
  echo 'error: --clean requires --linux' >&2
  exit 1
fi

run() {
  echo "+ $*"
  "$@"
}

run flutter pub get
run dart format --output=none --set-exit-if-changed lib test tool
run flutter analyze --no-pub
run cargo fmt --manifest-path native/music_core/Cargo.toml --check
run cargo clippy --locked --manifest-path native/music_core/Cargo.toml --all-targets -- -D warnings
# Flutter scanner tests load the native library built here.
run cargo build --locked --manifest-path native/music_core/Cargo.toml
run flutter test --no-pub
run cargo test --locked --manifest-path native/music_core/Cargo.toml

if $check_linux; then
  if $clean_linux; then
    run rm -rf build/linux
  fi
  run flutter build linux --release --no-pub --target tool/font_probe.dart
  run scripts/check_linux_fonts.sh
  run flutter build linux --release --no-pub
  run scripts/smoke_linux_bundle.sh
fi
