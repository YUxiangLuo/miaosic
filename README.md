# Miaosic

Miaosic is a local-first music player prototype. The current MVP focuses on:

- scanning a local FLAC library
- detecting album folders vs playlist-like folders
- storing the library in SQLite
- browsing tracks, albums, and playlists
- playing local files on Linux with `media_kit`

The scanner core is implemented in Rust under `native/music_core` and is called
from Flutter through FFI. Dart keeps a fallback scanner for environments where
the Rust dynamic library is unavailable.

## Development Library

The app currently uses this development root:

```text
/mnt/data/music
```

On first launch, Miaosic scans this folder and writes the library database to
the platform application support directory as `miaosic.db`.

## Run

```sh
flutter run -d linux
```

## Verify Scanner

The scanner can be tested without opening the UI:

```sh
dart run tool/scan_dev.dart /mnt/data/music
```

For the current development library, the expected shape is around:

```text
tracks=3389
engine=rust
folders=163
album_folders=133
playlist_folders=30
albums=133
```

## Checks

```sh
flutter analyze
flutter test
flutter build linux --debug
cargo check --manifest-path native/music_core/Cargo.toml
```
