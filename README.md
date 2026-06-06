# Miaosic

Miaosic is a Linux-only, local-first music player prototype. The current MVP
focuses on:

- scanning a local FLAC library
- detecting album folders vs playlist-like folders
- caching local cover art for smooth browsing
- storing the library in SQLite
- browsing tracks, albums, and playlists
- playing local files on Linux with `media_kit`

The scanner core is implemented in Rust under `native/music_core` and is called
from Flutter through FFI. The Rust dynamic library is required at runtime.

## Platform Scope

Linux is the only supported runtime target for this prototype. The repository
still contains Flutter's generated Android, iOS, macOS, Windows, and web
scaffolding, but those platforms are not maintained or verified.

## Development Library

The app defaults to the current user's Music folder:

```text
$HOME/Music
```

On first launch, Miaosic scans this folder and writes the library database to
the platform application support directory as `miaosic.db`. Cover art is cached
in the same support directory under `covers/`; the UI requests downsampled image
decodes while rendering lists and grids.

The music root can be changed from the Library panel in the app. The selected
folder is stored in the local SQLite database and reused on the next launch.

## Run

```sh
flutter run -d linux
```

## Verify Scanner

The scanner can be tested without opening the UI:

```sh
dart run tool/scan_dev.dart
```

The output shape is:

```text
tracks=<number of FLAC tracks>
engine=rust
folders=<number of folders>
album_folders=<number of album folders>
playlist_folders=<number of playlist folders>
albums=<number of detected albums>
covers_cached=<number of newly written cover files>
```

## Checks

```sh
flutter analyze
flutter test
flutter build linux --debug
cargo check --manifest-path native/music_core/Cargo.toml
```
