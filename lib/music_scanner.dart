import 'dart:async';
import 'dart:isolate';

import 'cover_cache.dart';
import 'models.dart';
import 'rust_music_scanner.dart';

typedef ScanProgressCallback = void Function(ScanProgress progress);
typedef RustScannerLoader = RustMusicScanner? Function();

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
  MusicScanner({this.rustScannerLoader = RustMusicScanner.tryLoad});

  final RustScannerLoader rustScannerLoader;
  RustMusicScanner? _rustScanner;

  Future<ScanResult> scan(
    String rootPath, {
    ScanProgressCallback? onProgress,
    List<Track>? previousTracks,
  }) async {
    final rustScanner = _loadRustScanner();
    if (rustScanner == null) {
      throw StateError(
        'Rust scanner dynamic library is required. Build native/music_core '
        'or run through the Linux Flutter bundle.',
      );
    }

    final cacheDir = await coverCacheDir();
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
    Isolate? worker;
    try {
      worker = await Isolate.spawn<List<Object?>>(_rustScanWorker, [
        rootPath,
        cacheDir,
        resultPort.sendPort,
        shouldForwardProgress ? progressPort?.sendPort : null,
        previousTracks,
      ]);
      final message = await resultPort.first;
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
      worker?.kill(priority: Isolate.immediate);
      resultPort.close();
      await progressSub?.cancel();
      progressPort?.close();
    }
  }

  RustMusicScanner? _loadRustScanner() {
    return _rustScanner ??= rustScannerLoader();
  }
}
