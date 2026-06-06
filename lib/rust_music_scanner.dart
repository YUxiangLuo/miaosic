import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

typedef _ScanLibraryNative =
    Pointer<Utf8> Function(Pointer<Utf8> rootPath, Pointer<Utf8> coverCacheDir);
typedef _ScanLibraryDart =
    Pointer<Utf8> Function(Pointer<Utf8> rootPath, Pointer<Utf8> coverCacheDir);
typedef _ProgressCallbackNative =
    Void Function(
      Uint64 filesSeen,
      Uint64 tracksParsed,
      Pointer<Utf8> currentPath,
    );
typedef _ScanLibraryWithProgressNative =
    Pointer<Utf8> Function(
      Pointer<Utf8> rootPath,
      Pointer<Utf8> coverCacheDir,
      Pointer<NativeFunction<_ProgressCallbackNative>> progressCallback,
    );
typedef _ScanLibraryWithProgressDart =
    Pointer<Utf8> Function(
      Pointer<Utf8> rootPath,
      Pointer<Utf8> coverCacheDir,
      Pointer<NativeFunction<_ProgressCallbackNative>> progressCallback,
    );
typedef _FreeStringNative = Void Function(Pointer<Utf8> value);
typedef _FreeStringDart = void Function(Pointer<Utf8> value);

typedef RustScanProgressCallback = void Function(ScanProgress progress);

class RustMusicScanner {
  RustMusicScanner._(DynamicLibrary library)
    : _scanLibrary = library
          .lookupFunction<_ScanLibraryNative, _ScanLibraryDart>(
            'miaosic_scan_library_with_covers',
          ),
      _scanLibraryWithProgress = _lookupScanLibraryWithProgress(library),
      _freeString = library.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'miaosic_free_string',
      );

  final _ScanLibraryDart _scanLibrary;
  final _ScanLibraryWithProgressDart? _scanLibraryWithProgress;
  final _FreeStringDart _freeString;

  static RustMusicScanner? tryLoad() {
    for (final candidate in _libraryCandidates()) {
      try {
        return RustMusicScanner._(DynamicLibrary.open(candidate));
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<ScanResult> scan(
    String rootPath,
    String coverCacheDir, {
    RustScanProgressCallback? onProgress,
  }) async {
    final rootPointer = rootPath.toNativeUtf8();
    final coverCachePointer = coverCacheDir.toNativeUtf8();
    NativeCallable<_ProgressCallbackNative>? progressCallback;
    Pointer<Utf8> responsePointer = nullptr;
    try {
      final progressScanner = _scanLibraryWithProgress;
      if (progressScanner != null && onProgress != null) {
        void handleProgress(
          int filesSeen,
          int tracksParsed,
          Pointer<Utf8> currentPath,
        ) {
          final path = currentPath == nullptr
              ? rootPath
              : currentPath.toDartString();
          onProgress(
            ScanProgress(
              filesSeen: filesSeen,
              tracksParsed: tracksParsed,
              currentPath: path,
            ),
          );
        }

        progressCallback = NativeCallable<_ProgressCallbackNative>.isolateLocal(
          handleProgress,
        );
        responsePointer = progressScanner(
          rootPointer,
          coverCachePointer,
          progressCallback.nativeFunction,
        );
      } else {
        responsePointer = _scanLibrary(rootPointer, coverCachePointer);
      }
      if (responsePointer == nullptr) {
        throw const FormatException('Rust scanner returned a null response');
      }
      final raw = responsePointer.toDartString();
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      if (decoded['ok'] != true) {
        throw StateError(decoded['error'] as String? ?? 'Rust scanner failed');
      }
      final result = decoded['result'] as Map<String, Object?>?;
      if (result == null) {
        throw const FormatException(
          'Rust scanner response did not include result',
        );
      }
      return _scanResultFromJson(result);
    } finally {
      calloc.free(rootPointer);
      calloc.free(coverCachePointer);
      if (responsePointer != nullptr) {
        _freeString(responsePointer);
      }
      progressCallback?.close();
    }
  }

  static _ScanLibraryWithProgressDart? _lookupScanLibraryWithProgress(
    DynamicLibrary library,
  ) {
    try {
      return library.lookupFunction<
        _ScanLibraryWithProgressNative,
        _ScanLibraryWithProgressDart
      >('miaosic_scan_library_with_covers_and_progress');
    } catch (_) {
      return null;
    }
  }

  static List<String> _libraryCandidates() {
    if (!Platform.isLinux) {
      return const [];
    }

    final executableDir = p.dirname(Platform.resolvedExecutable);
    final cwd = Directory.current.path;
    return [
      'libmusic_core.so',
      p.join(executableDir, 'lib', 'libmusic_core.so'),
      p.join(
        cwd,
        'build',
        'linux',
        'x64',
        'debug',
        'bundle',
        'lib',
        'libmusic_core.so',
      ),
      p.join(
        cwd,
        'native',
        'music_core',
        'target',
        'debug',
        'libmusic_core.so',
      ),
      p.join(
        cwd,
        'native',
        'music_core',
        'target',
        'release',
        'libmusic_core.so',
      ),
    ];
  }
}

ScanResult _scanResultFromJson(Map<String, Object?> json) {
  return ScanResult(
    rootPath: json['root_path'] as String,
    engine: 'rust',
    tracks: _list(json['tracks']).map(_trackFromJson).toList(),
    folders: _list(json['folders']).map(_folderFromJson).toList(),
    albums: _list(json['albums']).map(_albumFromJson).toList(),
    elapsed: Duration(milliseconds: _int(json['elapsed_ms']) ?? 0),
    coversCached: _int(json['covers_cached']) ?? 0,
  );
}

Track _trackFromJson(Map<String, Object?> json) {
  return Track(
    path: json['path'] as String,
    folderPath: json['folder_path'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    album: json['album'] as String,
    albumArtist: json['album_artist'] as String,
    trackNumber: _int(json['track_number']),
    discNumber: _int(json['disc_number']),
    year: _int(json['year']),
    durationMs: _int(json['duration_ms']),
    sizeBytes: _int(json['size_bytes']) ?? 0,
    modifiedMs: _int(json['modified_ms']) ?? 0,
    coverArtPath: json['cover_art_path'] as String?,
  );
}

FolderSummary _folderFromJson(Map<String, Object?> json) {
  return FolderSummary(
    path: json['path'] as String,
    name: json['name'] as String,
    kind: FolderKind.fromDb(json['kind'] as String),
    confidence: _double(json['confidence']),
    trackCount: _int(json['track_count']) ?? 0,
    albumCount: _int(json['album_count']) ?? 0,
    albumArtistCount: _int(json['album_artist_count']) ?? 0,
    artistCount: _int(json['artist_count']) ?? 0,
    yearCount: _int(json['year_count']) ?? 0,
    coverArtPath: json['cover_art_path'] as String?,
  );
}

AlbumSummary _albumFromJson(Map<String, Object?> json) {
  return AlbumSummary(
    folderPath: json['folder_path'] as String,
    title: json['title'] as String,
    albumArtist: json['album_artist'] as String,
    year: _int(json['year']),
    trackCount: _int(json['track_count']) ?? 0,
    coverArtPath: json['cover_art_path'] as String?,
  );
}

Iterable<Map<String, Object?>> _list(Object? value) {
  return (value as List<Object?>).cast<Map<String, Object?>>();
}

int? _int(Object? value) {
  if (value == null) {
    return null;
  }
  return (value as num).toInt();
}

double _double(Object? value) {
  return (value as num).toDouble();
}
