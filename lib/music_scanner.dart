import 'dart:async';
import 'dart:isolate';

import 'cover_cache.dart';
import 'models.dart';
import 'rust_music_scanner.dart';

typedef ScanProgressCallback = void Function(ScanProgress progress);
typedef RustScannerLoader = RustMusicScanner? Function();

class ScanCancelledException implements Exception {
  const ScanCancelledException();

  @override
  String toString() => 'Scan cancelled';
}

Future<void> _rustScanWorker(List<Object?> message) async {
  final rootPath = message[0] as String;
  final coverCacheDir = message[1] as String;
  final resultPort = message[2] as SendPort;
  final progressPort = message[3] as SendPort?;
  final previousTracks = (message[4] as List<Object?>?)?.cast<Track>();

  try {
    final scanner = RustMusicScanner.tryLoad();
    if (scanner == null) {
      throw StateError('Rust scanner is unavailable in worker isolate');
    }
    final result = await scanner.scan(
      rootPath,
      coverCacheDir,
      previousTracks: previousTracks,
      onProgress: progressPort == null
          ? null
          : (progress) {
              progressPort.send([
                progress.filesSeen,
                progress.tracksParsed,
                progress.currentPath,
              ]);
            },
    );
    resultPort.send([true, result]);
  } catch (error, stackTrace) {
    resultPort.send([false, error.toString(), stackTrace.toString()]);
  }
}

class MusicScanner {
  MusicScanner({
    this.rustScannerLoader = RustMusicScanner.tryLoad,
    CoverCacheDirectoryProvider? cacheDirectoryProvider,
  }) : _cacheDirectoryProvider = cacheDirectoryProvider ?? coverCacheDir;

  final RustScannerLoader rustScannerLoader;
  final CoverCacheDirectoryProvider _cacheDirectoryProvider;
  RustMusicScanner? _rustScanner;
  Isolate? _worker;
  Completer<Object?>? _resultCompleter;
  bool _cancelRequested = false;

  void cancel() {
    _cancelRequested = true;
    final worker = _worker;
    _worker = null;
    worker?.kill(priority: Isolate.immediate);
    final completer = _resultCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const ScanCancelledException());
    }
  }

  void prepareForScan() {
    if (_resultCompleter != null) {
      return;
    }
    _cancelRequested = false;
  }

  Future<ScanResult> scan(
    String rootPath, {
    ScanProgressCallback? onProgress,
    List<Track>? previousTracks,
  }) async {
    if (_resultCompleter != null) {
      throw StateError('A scan is already running');
    }
    if (_cancelRequested) {
      throw const ScanCancelledException();
    }

    final rustScanner = _loadRustScanner();
    if (rustScanner == null) {
      throw StateError(
        'Rust scanner dynamic library is required. Build native/music_core '
        'or run through the Linux Flutter bundle.',
      );
    }

    final cacheDir = await _cacheDirectoryProvider();
    if (_cancelRequested) {
      throw const ScanCancelledException();
    }
    onProgress?.call(
      ScanProgress(filesSeen: 0, tracksParsed: 0, currentPath: rootPath),
    );

    final shouldForwardProgress = onProgress != null;
    final progressPort = shouldForwardProgress ? ReceivePort() : null;
    StreamSubscription<Object?>? progressSub;
    final progressListener = onProgress;
    if (progressPort != null && progressListener != null) {
      progressSub = progressPort.listen((message) {
        if (message case [
          final int filesSeen,
          final int tracksParsed,
          final String path,
        ]) {
          progressListener(
            ScanProgress(
              filesSeen: filesSeen,
              tracksParsed: tracksParsed,
              currentPath: path,
            ),
          );
        }
      });
    }

    final resultPort = ReceivePort();
    final resultCompleter = Completer<Object?>();
    _resultCompleter = resultCompleter;
    StreamSubscription<Object?>? resultSub;
    Isolate? worker;
    try {
      resultSub = resultPort.listen((message) {
        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(message);
        }
      });
      worker = await Isolate.spawn<List<Object?>>(_rustScanWorker, [
        rootPath,
        cacheDir,
        resultPort.sendPort,
        shouldForwardProgress ? progressPort?.sendPort : null,
        previousTracks,
      ]);
      if (_cancelRequested) {
        worker.kill(priority: Isolate.immediate);
        throw const ScanCancelledException();
      }
      _worker = worker;
      final message = await resultCompleter.future;
      final result = switch (message) {
        [true, final ScanResult result] => result,
        [false, final String error, _] => throw StateError(error),
        _ => throw const FormatException('Unexpected Rust scanner response'),
      };
      onProgress?.call(
        ScanProgress(
          filesSeen: result.tracks.length,
          tracksParsed: result.tracks.length,
          currentPath: rootPath,
        ),
      );
      return result;
    } finally {
      _worker = null;
      _resultCompleter = null;
      worker?.kill(priority: Isolate.immediate);
      await resultSub?.cancel();
      resultPort.close();
      await progressSub?.cancel();
      progressPort?.close();
    }
  }

  RustMusicScanner? _loadRustScanner() {
    return _rustScanner ??= rustScannerLoader();
  }
}
