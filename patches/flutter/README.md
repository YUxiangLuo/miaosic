# Pinned Flutter Linux engine patch

See [build, diagnostics, scope, and measurements](../../docs/performance/cd-rotation.md).

The patch applies at the Flutter repository root at the engine revision in
`engine.json`. It uses engine source changes and public EGL, GTK, Wayland, and
Flutter embedder APIs; it does not depend on private object offsets, binary
rewriting, or preload hooks.

The build helper enables `--enable-fontconfig`, as required by upstream
`ci/builders/linux_host_desktop_engine.json` for all desktop build modes. Without
it, finding a Latin font does not imply that Chinese fallback will work.
`build_recipe` version 2 invalidates the earlier artifacts that omitted this
flag. When changing native build flags, increment that version so local and CI
caches cannot reuse a binary built with the old configuration.

Flutter code is covered by the upstream BSD license, reproduced in
`FLUTTER-LICENSE`. The generated presentation-time protocol files retain their
own MIT license notices, also reproduced in `WAYLAND-PROTOCOL-LICENSE`. Both
licenses are included in the app bundle. The protocol files were generated from the stable presentation-time
XML using `wayland-scanner client-header` and `private-code`. The client wrappers
use `wl_proxy_marshal` / `wl_proxy_marshal_constructor` instead of the newer
`wl_proxy_marshal_flags` for compatibility with Flutter's Wayland 1.18 sysroot.
The implementation binds presentation-time version 1. The generated C source
includes its generated header when compiled as C++ to preserve C linkage.
