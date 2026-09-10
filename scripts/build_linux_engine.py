#!/usr/bin/env python3
"""Build the pinned Wayland engine without modifying the installed Flutter SDK."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "patches/flutter/linux-wayland-frame-sync.patch"
PIN = json.loads((PATCH.parent / "engine.json").read_text())
LIBRARY = "libflutter_linux_gtk.so"


def run(*args, cwd=None, env=None):
    print("+", " ".join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def valid(directory, fingerprint):
    try:
        return (
            (directory / "fingerprint").read_text().strip() == fingerprint
            and (directory / "sha256").read_text().strip()
            == digest(directory / LIBRARY)
        )
    except FileNotFoundError:
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["debug", "profile", "release"], default="release")
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 10))
    parser.add_argument("--source-dir", type=Path, help="Reuse an isolated engine checkout at the pinned revision")
    parser.add_argument("--depot-tools", type=Path, help="Reuse depot_tools at the pinned revision")
    args = parser.parse_args()
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        parser.error("The patched engine currently supports Linux x64 builds.")
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    flutter = shutil.which("flutter")
    if not flutter:
        parser.error("Put Flutter on PATH first.")
    sdk = Path(flutter).resolve().parents[1]
    revision = PIN["engine_revision"]
    if (sdk / "bin/cache/engine.stamp").read_text().strip() != revision:
        parser.error(f"Use Flutter {PIN['flutter_version']}; its engine must be {revision}.")

    patch_bytes = PATCH.read_bytes()
    patch_hash = hashlib.sha256(patch_bytes).hexdigest()
    fingerprint = f"{revision}:{patch_hash}:{args.mode}:{PIN['build_recipe']}"
    destination = ROOT / ".dart_tool/miaosic_engine" / args.mode
    if valid(destination, fingerprint):
        print(f"Patched {args.mode} engine is ready: {destination / LIBRARY}")
        return
    cache = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "miaosic/flutter-engine"
    artifact = cache / "artifacts" / hashlib.sha256(fingerprint.encode()).hexdigest()
    if not valid(artifact, fingerprint):
        source = args.source_dir.resolve() if args.source_dir else cache / revision
        depot = args.depot_tools.resolve() if args.depot_tools else cache / "depot_tools"
        if source.resolve() == sdk:
            parser.error("Use an isolated source checkout, not the installed Flutter SDK.")
        cache.mkdir(parents=True, exist_ok=True)
        if not (source / ".git").exists():
            source.mkdir(parents=True, exist_ok=True)
            run("git", "init", source)
            run("git", "remote", "add", "origin", "https://github.com/flutter/flutter.git", cwd=source)
            run("git", "fetch", "--depth=1", "origin", revision, cwd=source)
            run("git", "checkout", "--detach", "FETCH_HEAD", cwd=source)
        actual_revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
        if actual_revision != revision:
            parser.error(f"Engine checkout {source} is at {actual_revision}, expected {revision}.")

        if not (depot / ".git").exists():
            run("git", "clone", "https://chromium.googlesource.com/chromium/tools/depot_tools.git", depot)
            run("git", "checkout", "--detach", PIN["depot_tools_revision"], cwd=depot)
        actual_depot = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=depot, text=True).strip()
        if actual_depot != PIN["depot_tools_revision"]:
            parser.error(f"depot_tools at {depot} must use revision {PIN['depot_tools_revision']}.")
        env = dict(os.environ, PATH=f"{depot}:{os.environ['PATH']}", DEPOT_TOOLS_UPDATE="0")
        config = {
            "name": ".", "url": "https://github.com/flutter/flutter.git",
            "managed": False, "deps_file": "DEPS", "custom_deps": {},
            "custom_vars": {"download_android_deps": False, "download_fuchsia_deps": False, "download_windows_deps": False},
        }
        (source / ".gclient").write_text(f"solutions = [{config!r}]\n")
        synced = source / ".miaosic-deps-synced"
        if not synced.exists() or synced.read_text().strip() != revision:
            run("gclient", "sync", "--no-history", f"-j{min(args.jobs, 8)}", cwd=source, env=env)
            synced.write_text(revision + "\n")

        # Never reset a caller's checkout. Accept an already applied patch;
        # otherwise require a clean application and preserve failures for review.
        applied = subprocess.run(["git", "apply", "--reverse", "--check", str(PATCH)], cwd=source, capture_output=True).returncode == 0
        previous_patch = source / ".miaosic-applied.patch"
        if not applied:
            if previous_patch.exists():
                run("git", "apply", "--reverse", "--check", previous_patch, cwd=source)
                run("git", "apply", "--reverse", previous_patch, cwd=source)
            run("git", "apply", "--check", PATCH, cwd=source)
            run("git", "apply", PATCH, cwd=source)
        shutil.copy2(PATCH, previous_patch)
        engine = source / "engine/src"
        # Match upstream linux_host_desktop_engine.json: Fontconfig supplies
        # system font discovery and per-character fallback, including CJK.
        run(sys.executable, "flutter/tools/gn", f"--runtime-mode={args.mode}", "--enable-fontconfig", "--no-lto", "--no-rbe", "--no-build-glfw-shell", cwd=engine, env=env)
        run("ninja", "-C", f"out/host_{args.mode}", "-j", args.jobs, "flutter_linux_gtk", cwd=engine, env=env)
        if PATCH.read_bytes() != patch_bytes:
            sys.exit("The engine patch changed during compilation. Rerun this command to build the final version.")
        artifact.mkdir(parents=True, exist_ok=True)
        shutil.copy2(engine / f"out/host_{args.mode}" / LIBRARY, artifact / LIBRARY)
        (artifact / "sha256").write_text(digest(artifact / LIBRARY) + "\n")
        (artifact / "fingerprint").write_text(fingerprint + "\n")

    destination.mkdir(parents=True, exist_ok=True)
    for name in (LIBRARY, "sha256", "fingerprint"):
        shutil.copy2(artifact / name, destination / name)
    print(f"Patched engine ready. Run: flutter build linux --{args.mode}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
