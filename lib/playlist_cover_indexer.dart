import 'dart:async';
import 'dart:isolate';

import 'cover_cache.dart';
import 'library_database.dart';
import 'models.dart';
import 'rust_music_scanner.dart';

typedef TrackCoverCacheUpdated = void Function(Map<String, String?> cache);
typedef TrackCoverExtractorStarter =
    Future<TrackCoverExtractor> Function(String cacheDir);

abstract interface class TrackCoverExtractor {
  Future<Map<String, String?>> extract(List<String> paths);

  void close();
}

Future<void> _extractTrackCoverWorker(List<Object?> message) async {
  final cacheDir = message[0] as String;
  final readyPort = message[1] as SendPort;
  final commandPort = ReceivePort();
  final scanner = RustMusicScanner.tryLoad();
  readyPort.send(commandPort.sendPort);

  await for (final rawMessage in commandPort) {
    if (rawMessage == null) {
      commandPort.close();
      break;
    }
    final request = rawMessage as List<Object?>;
    final paths = (request[0] as List<Object?>).cast<String>();
    final resultPort = request[1] as SendPort;

    try {
      if (scanner == null) {
        throw StateError('Rust cover extractor is unavailable');
      }
      final results = await scanner.extractTrackCovers(paths, cacheDir);
      resultPort.send([
        true,
        results.map((result) => [result.path, result.coverArtPath]).toList(),
      ]);
    } catch (error, stackTrace) {
      resultPort.send([false, error.toString(), stackTrace.toString()]);
    }
  }
}

class TrackCoverIndexer {
  TrackCoverIndexer({
    TrackCoverExtractorStarter? startExtractor,
    CoverCacheDirectoryProvider? cacheDirectoryProvider,
    int batchSize = 24,
    Duration? batchDelay,
    Duration? pauseDelay,
  }) : _startExtractor =
           startExtractor ??
           ((cacheDir) => _IsolateTrackCoverExtractor.start(cacheDir)),
       _cacheDirectoryProvider = cacheDirectoryProvider ?? coverCacheDir,
       _batchSize = batchSize,
       _batchDelay = batchDelay ?? const Duration(milliseconds: 90),
       _pauseDelay = pauseDelay ?? const Duration(milliseconds: 500) {
    if (batchSize <= 0) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
    }
  }

  final TrackCoverExtractorStarter _startExtractor;
  final CoverCacheDirectoryProvider _cacheDirectoryProvider;
  final int _batchSize;
  final Duration _batchDelay;
  final Duration _pauseDelay;

  int _generation = 0;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _generation++;
  }

  void cancel() {
    _generation++;
  }

  Future<bool> indexTracks({
    required List<Track> tracks,
    required LibraryDatabase database,
    Map<String, String?>? knownCache,
    required bool Function() shouldPause,
    required TrackCoverCacheUpdated onCacheUpdated,
  }) async {
    final generation = ++_generation;
    if (tracks.isEmpty) {
      return true;
    }

    final cached = knownCache ?? await database.loadTrackCoverCache(tracks);
    if (!_isCurrent(generation)) {
      return false;
    }
    if (knownCache == null && cached.isNotEmpty) {
      onCacheUpdated(cached);
    }

    final pending = tracks
        .where((track) => !cached.containsKey(track.path))
        .toList(growable: false);
    if (pending.isEmpty) {
      return true;
    }

    final cacheDir = await _cacheDirectoryProvider();
    if (!_isCurrent(generation)) {
      return false;
    }
    final worker = await _startExtractor(cacheDir);
    try {
      for (var start = 0; start < pending.length; start += _batchSize) {
        while (_isCurrent(generation) && shouldPause()) {
          await Future<void>.delayed(_pauseDelay);
        }
        if (!_isCurrent(generation)) {
          return false;
        }

        final batch = pending
            .skip(start)
            .take(_batchSize)
            .toList(growable: false);
        final extracted = await worker.extract(
          batch.map((track) => track.path).toList(growable: false),
        );
        if (!_isCurrent(generation) || extracted.isEmpty) {
          return false;
        }

        final byPath = {for (final track in batch) track.path: track};
        final entries = <TrackCoverCacheEntry>[];
        final updates = <String, String?>{};
        for (final result in extracted.entries) {
          final track = byPath[result.key];
          if (track == null) {
            continue;
          }
          entries.add(
            TrackCoverCacheEntry(
              path: track.path,
              sizeBytes: track.sizeBytes,
              modifiedMs: track.modifiedMs,
              coverArtPath: result.value,
            ),
          );
          updates[track.path] = result.value;
        }
        if (entries.isEmpty) {
          continue;
        }

        await database.saveTrackCoverCache(entries);
        if (!_isCurrent(generation)) {
          return false;
        }
        onCacheUpdated(updates);
        await Future<void>.delayed(_batchDelay);
      }
      return true;
    } finally {
      worker.close();
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;
}

class _IsolateTrackCoverExtractor implements TrackCoverExtractor {
  _IsolateTrackCoverExtractor._(this._sendPort, this._isolate);

  final SendPort _sendPort;
  final Isolate _isolate;

  static Future<_IsolateTrackCoverExtractor> start(String cacheDir) async {
    final readyPort = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<List<Object?>>(_extractTrackCoverWorker, [
        cacheDir,
        readyPort.sendPort,
      ]);
      final sendPort = await readyPort.first as SendPort;
      return _IsolateTrackCoverExtractor._(sendPort, isolate);
    } finally {
      readyPort.close();
    }
  }

  @override
  Future<Map<String, String?>> extract(List<String> paths) async {
    final resultPort = ReceivePort();
    try {
      _sendPort.send([paths, resultPort.sendPort]);
      final message = await resultPort.first;
      return switch (message) {
        [true, final List<Object?> rawResults] => {
          for (final raw in rawResults)
            if (raw case [final String path, final String? coverArtPath])
              path: coverArtPath,
        },
        [false, final String error, _] => throw StateError(error),
        _ => throw const FormatException(
          'Unexpected Rust cover extractor response',
        ),
      };
    } finally {
      resultPort.close();
    }
  }

  @override
  void close() {
    _sendPort.send(null);
    _isolate.kill(priority: Isolate.immediate);
  }
}
