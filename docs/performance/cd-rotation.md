# CD rotation and Linux frame synchronization

## Diagnosis

On 2026-09-08, the original application was tested on Arch Linux, Hyprland
Wayland, Intel Arc B570 (xe, Mesa 26.2.2), at 2560 × 1440, 100 Hz, DPR 1,
with VRR disabled. Flutter was 3.47.1. The full album page, an isolated rotating
cover, and a rotating solid square all ran at 60 FPS. Changing Impeller to Skia
did not remove that limit. The album page's UI and raster work comfortably fit
within 10 ms; these measurements do not point to insufficient GPU throughput.

The pinned Linux embedder did not supply `FlutterProjectArgs.vsync_callback`.
It therefore used `VsyncWaiterFallback`, whose interval is fixed at 1/60 second.
GTK's separate repaint clock also ran at approximately 60 Hz on this machine.
Driving only Dart/engine callbacks at 100 Hz left presentation limited by GTK.
`AnimationController(vsync: this)` connects to that engine clock; it cannot fix
the underlying Linux scheduling. An 18-second rotation should keep its duration
when the monitor's refresh rate changes.

At 100 Hz without VRR, 60 distinct frames per second cannot have equal display
durations. This explains continuous uneven motion despite short rendering times.
It does not rule out every possible driver or compositor issue on other systems.

Upstream references:

- [Pinned engine source](https://github.com/flutter/flutter/tree/5d531788691ec3404cac0cee66ead4007b177363/engine/src/flutter/shell/platform/linux)
- [Fallback vsync implementation](https://github.com/flutter/flutter/blob/5d531788691ec3404cac0cee66ead4007b177363/engine/src/flutter/shell/common/vsync_waiter_fallback.cc)
- [Flutter desktop refresh synchronization issue](https://github.com/flutter/flutter/issues/49757)
- [Wayland frame callback protocol](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_surface-request-frame)
- [Presentation feedback protocol](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/stable/presentation-time/presentation-time.xml)

## Implementation

`patches/flutter/linux-wayland-frame-sync.patch` changes the pinned engine's
Linux embedder. A Wayland child surface presents Flutter's shared EGL image
directly, independently of GTK's repaint timer. GTK still handles input and
window management; the child has an empty input region. Wayland frame callbacks
drive engine vsync, with presentation timestamps providing a more precise time
base when the compositor exposes a monotonic presentation clock. The current
monitor supplies the refresh interval; 100 Hz is not hardcoded.

Startup and hidden-window timeouts keep pending engine requests from stalling.
Idle scenes do not start a continuous rendering loop. Remapping recreates the
child after GTK has replaced its parent surface and restores the last buffer
even if the scene is paused. Teardown returns pending vsync
batons before releasing the renderer. EGL state is restored after presentation.

This patch targets Miaosic's single Flutter view on Linux x64/Wayland. X11,
software rendering, and systems where the Wayland/EGL path cannot initialize
retain GTK rendering and the 60 Hz fallback. Multiple monitors with different
refresh rates, VRR, fractional scaling, and other compositors require additional
hardware testing. Do not interpret the tested 100 Hz result as validation of
every display configuration.

Additional Dart changes stop hidden library-page tickers and painting while
preserving its state, avoid repeating rotation on unrelated updates, stop
inactive covers, decode the large cover at its actual device pixel density,
and dispose palette extraction resources on both success and failure.

## Build and maintenance

Use the SDK version and engine revision in `patches/flutter/engine.json`.
The build helper downloads a separate source tree and pinned depot_tools,
applies the patch, and builds `flutter_linux_gtk` using Flutter's Debian sysroot.
It never replaces the SDK's cached engine. Build prerequisites are listed in
the main README. The first build uses several GB of disk space and takes much
longer than compiling the application; `--jobs` controls parallel compilation.

```sh
python3 scripts/build_linux_engine.py --mode release
flutter build linux --release
```

Prepare `--mode debug` for `flutter run -d linux`, or `--mode profile` for a
profile build. CMake checks the engine revision, patch fingerprint, mode, and
library checksum before linking and bundling. An ordinary subsequent
`flutter build linux --release` uses the prepared library automatically.
CI and release workflows prepare and cache the same engine.

Source and artifact caches live under
`${XDG_CACHE_HOME:-$HOME/.cache}/miaosic/flutter-engine/`. Project artifacts live
in `.dart_tool/miaosic_engine/<mode>/`. After `flutter clean`, rerun the helper;
it can restore the cached binary without recompiling. `--source-dir` and
`--depot-tools` can reuse existing isolated checkouts at the pinned revisions.
Never pass the installed SDK as the source directory.

When changing the patch, rerun the helper. It can reverse its previously
recorded patch before applying the new one, and fails instead of resetting
unexpected conflicting edits. An SDK upgrade requires rebasing and testing the
patch against the new engine revision and updating the pin and CI together.

For a runtime A/B comparison or compatibility fallback, use:

```sh
FLUTTER_LINUX_DISABLE_WAYLAND_FRAME_SYNC=1 build/linux/x64/release/bundle/miaosic
```

For development with the stock SDK engine, explicitly opt out at build time:

```sh
MIAOSIC_USE_SYSTEM_FLUTTER_ENGINE=1 flutter build linux --profile
```

This opt-out disables the native synchronization fix. Remove the environment
variable and rebuild to use the prepared patched engine again.

## Repeatable measurements

The probe imports the real `AlbumPlaybackView`, uses a supplied cover and twelve
synthetic tracks, and never opens audio or a library database. It measures the
album page, a single rotating image, and a rotating square, each with a
three-second warmup and ten-second sample. It exits after about 39 seconds.
Keep the window visible throughout; obscured windows can be throttled by the
compositor. Run it without a concurrent compilation for useful timing data.

```sh
python3 scripts/build_linux_engine.py --mode profile
flutter build linux --profile -t tool/frame_probe.dart
GDK_BACKEND=wayland \
  MIAOSIC_DIAG_COVER=/absolute/path/to/cover.jpg \
  MIAOSIC_DIAG_OUTPUT=/tmp/miaosic-frame-probe.json \
  FLUTTER_LINUX_FRAME_TIMINGS=/tmp/miaosic-present.csv \
  build/linux/x64/profile/bundle/miaosic
python3 scripts/analyze_frame_timings.py /tmp/miaosic-present.csv
```

The JSON reports engine/UI/raster timing. The CSV records buffer submissions
and actual compositor presentation feedback; a Dart frame count alone is not
proof of displayed FPS. The analyzer defaults to the first scene's steady
sample; `--warmup 16` selects the second scene and `--warmup 29` the third.
The optional trace is also available in the normal release application.
Presentation feedback depends on compositor support. After building the probe,
build the regular application again with `flutter build linux --profile`.

First native patched-engine measurement on the machine above:

| Full album page, profile | Before | Patched |
| --- | ---: | ---: |
| Engine FPS | 60.00 | 100.011 |
| UI median, ms | 0.293 | 0.160 |
| Raster median, ms | 1.219 | 0.889 |
| Raster p99, ms | 1.627 | 1.389 |

The patched presentation sample contained 1,000 displayed frames: 100.011 FPS,
9.999 ms median interval, 10.003 ms p99, 10.005 ms maximum, and zero gaps longer
than 1.5 refresh periods. Feedback flags were 7 (vsync, hardware clock, hardware
completion). UI/raster timings exclude some platform/compositor work; actual
presentation intervals are the relevant evidence for the cadence improvement.
These are a short controlled measurement, not a guarantee of zero missed frames
under all workloads. Widget tests cover pause/resume angle continuity, inactive
animation shutdown, and restoration of the hidden library page.

The final **release** probe also ran at 100.011 engine FPS. Its first ten-second
presentation sample displayed 999 frames (99.911 FPS), with one 19.998 ms gap;
median/p99 intervals were 9.999/10.001 ms. This demonstrates the difference
between engine scheduling and actual display delivery, and leaves room for
occasional compositor or system scheduling misses. The album's UI/raster
medians were 0.149/0.924 ms. Summary data tied to the final patch hash is in
[`cd-rotation-results.json`](cd-rotation-results.json).

Native integration checks exercised resize, hide, show, fullscreen, and normal
close. An idle release window also restored its last image after hide/show
without needing a repeating animation. All three build modes were compiled;
`flutter analyze` and 165 Flutter tests passed. The bundle smoke script runs
the X11 fallback in Xvfb with isolated app data; Wayland behavior was checked
on the real compositor separately.

## System font fallback regression

On 2026-09-10, a missing build flag was found in the initial custom-engine build:
`--enable-fontconfig`. Upstream's Linux desktop builds explicitly enable it;
the generic engine build helper defaults to disabling it. System CJK fonts were
installed, but the custom engine could not select them for Chinese characters.
The Wayland presentation patch itself does not select fonts.

Build recipe 2 enables Fontconfig in debug, profile, and release and invalidates
the older cached engines. `tool/font_probe.dart` renders eight Chinese characters
with the actual bundled engine, rejects empty/missing glyphs and identical tofu
boxes, and exits unsuccessfully when fallback is broken. It reproduced the old
engine failure on the character `中`. CI installs CJK fonts and runs this probe
before rebuilding and packaging the normal application. Widget tests alone do
not cover a custom native engine's font configuration.

The corrected debug, profile, and release engines passed the native glyph check
on both Wayland and X11 with this machine's existing CJK fonts. The recipe 2
profile animation check also displayed 1,000 frames in the ten-second sample:
100.011 FPS, 9.999 ms median interval, 10.001 ms p99, and 10.004 ms maximum, with
no gaps longer than 1.5 refresh periods. Restart the player after rebuilding:
an already-running process keeps its loaded engine.
