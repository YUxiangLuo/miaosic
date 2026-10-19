import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'app_diagnostics.dart';
import 'models.dart';
import 'rust_scanner_codec.dart';

export 'rust_scanner_codec.dart' show RustTrackCoverResult;

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
typedef _ScanLibraryIncrementalWithProgressNative =
    Pointer<Utf8> Function(
      Pointer<Utf8> rootPath,
      Pointer<Utf8> previousTracksJson,
      Pointer<Utf8> coverCacheDir,
      Pointer<NativeFunction<_ProgressCallbackNative>> progressCallback,
    );
typedef _ScanLibraryIncrementalWithProgressDart =
    Pointer<Utf8> Function(
      Pointer<Utf8> rootPath,
      Pointer<Utf8> previousTracksJson,
      Pointer<Utf8> coverCacheDir,
      Pointer<NativeFunction<_ProgressCallbackNative>> progressCallback,
    );
typedef _ExtractTrackCoversNative =
    Pointer<Utf8> Function(
      Pointer<Utf8> pathsJson,
      Pointer<Utf8> coverCacheDir,
    );
typedef _ExtractTrackCoversDart =
    Pointer<Utf8> Function(
      Pointer<Utf8> pathsJson,
      Pointer<Utf8> coverCacheDir,
    );
typedef _FreeStringNative = Void Function(Pointer<Utf8> value);
typedef _FreeStringDart = void Function(Pointer<Utf8> value);

typedef RustScanProgressCallback = void Function(ScanProgress progress);

class RustMusicScanner {
  static const expectedAbiVersion = 1;

  factory RustMusicScanner.open(String libraryPath) {
    final library = DynamicLibrary.open(libraryPath);
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'miaosic_abi_version',
    )();
    if (version != expectedAbiVersion) {
      throw StateError(
        'Rust scanner ABI $version does not match $expectedAbiVersion: $libraryPath',
      );
    }
    return RustMusicScanner._(library, libraryPath, version);
  }

  RustMusicScanner._(DynamicLibrary library, this.libraryPath, this.abiVersion)
    : _scanLibraryWithProgress = library
          .lookupFunction<
            _ScanLibraryWithProgressNative,
            _ScanLibraryWithProgressDart
          >('miaosic_scan_library_with_covers_and_progress'),
      _scanLibraryIncrementalWithProgress = library
          .lookupFunction<
            _ScanLibraryIncrementalWithProgressNative,
            _ScanLibraryIncrementalWithProgressDart
          >('miaosic_scan_library_incremental_with_covers_and_progress'),
      _extractTrackCovers = library
          .lookupFunction<_ExtractTrackCoversNative, _ExtractTrackCoversDart>(
            'miaosic_extract_track_covers',
          ),
      _freeString = library.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'miaosic_free_string',
      );

  final String libraryPath;
  final int abiVersion;
  final _ScanLibraryWithProgressDart _scanLibraryWithProgress;
  final _ScanLibraryIncrementalWithProgressDart
  _scanLibraryIncrementalWithProgress;
  final _ExtractTrackCoversDart _extractTrackCovers;
  final _FreeStringDart _freeString;

  static RustMusicScanner? tryLoad() {
    final failures = <String>[];
    StackTrace? lastStack;
    for (final candidate in _libraryCandidates()) {
      try {
        return RustMusicScanner.open(candidate);
      } catch (error, stackTrace) {
        failures.add('$candidate: $error');
        lastStack = stackTrace;
      }
    }
    if (failures.isNotEmpty) {
      reportAppError(
        'load Rust scanner',
        StateError(failures.join('\n')),
        lastStack!,
      );
    }
    return null;
  }

  Future<ScanResult> scan(
    String rootPath,
    String coverCacheDir, {
    RustScanProgressCallback? onProgress,
    List<Track>? previousTracks,
  }) async {
    final rootPointer = rootPath.toNativeUtf8();
    final coverCachePointer = coverCacheDir.toNativeUtf8();
    final previousTracksPointer = previousTracks == null
        ? nullptr.cast<Utf8>()
        : jsonEncode({
            'previous_tracks': [
              for (final track in previousTracks) encodeRustTrack(track),
            ],
          }).toNativeUtf8();
    NativeCallable<_ProgressCallbackNative>? progressCallback;
    Pointer<Utf8> responsePointer = nullptr;
    try {
      Pointer<NativeFunction<_ProgressCallbackNative>> progressPointer = nullptr
          .cast<NativeFunction<_ProgressCallbackNative>>();
      if (onProgress != null) {
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
        progressPointer = progressCallback.nativeFunction;
      }

      responsePointer = previousTracks != null && previousTracks.isNotEmpty
          ? _scanLibraryIncrementalWithProgress(
              rootPointer,
              previousTracksPointer,
              coverCachePointer,
              progressPointer,
            )
          : _scanLibraryWithProgress(
              rootPointer,
              coverCachePointer,
              progressPointer,
            );
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
      return decodeRustScanResult(result);
    } finally {
      calloc.free(rootPointer);
      calloc.free(coverCachePointer);
      if (previousTracksPointer != nullptr) {
        calloc.free(previousTracksPointer);
      }
      if (responsePointer != nullptr) {
        _freeString(responsePointer);
      }
      progressCallback?.close();
    }
  }

  Future<List<RustTrackCoverResult>> extractTrackCovers(
    List<String> paths,
    String coverCacheDir,
  ) async {
    final pathsPointer = jsonEncode({'paths': paths}).toNativeUtf8();
    final coverCachePointer = coverCacheDir.toNativeUtf8();
    Pointer<Utf8> responsePointer = nullptr;
    try {
      responsePointer = _extractTrackCovers(pathsPointer, coverCachePointer);
      if (responsePointer == nullptr) {
        throw const FormatException('Rust cover extractor returned null');
      }
      final raw = responsePointer.toDartString();
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      if (decoded['ok'] != true) {
        throw StateError(
          decoded['error'] as String? ?? 'Rust cover extractor failed',
        );
      }
      final result = decoded['result'] as List<Object?>?;
      if (result == null) {
        throw const FormatException(
          'Rust cover extractor response did not include result',
        );
      }
      return result
          .cast<Map<String, Object?>>()
          .map(RustTrackCoverResult.fromJson)
          .toList();
    } finally {
      calloc.free(pathsPointer);
      calloc.free(coverCachePointer);
      if (responsePointer != nullptr) {
        _freeString(responsePointer);
      }
    }
  }

  static List<String> _libraryCandidates() {
    if (!Platform.isLinux) {
      return const [];
    }

    final executableDir = p.dirname(Platform.resolvedExecutable);
    final cwd = Directory.current.path;
    return [
      p.join(executableDir, 'lib', 'libmusic_core.so'),
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
      'libmusic_core.so',
    ];
  }
}
