import 'dart:async';
import 'dart:isolate';

import 'cover_cache.dart';
import 'library_database.dart';
import 'models.dart';
import 'rust_music_scanner.dart';

typedef TrackCoverCacheUpdated = void Function(Map<String, String?> cache);

Future<void> _extractTrackCoverWorker(List<Object?> message) async {
  final paths = (message[0] as List<Object?>).cast<String>();
  final cacheDir = message[1] as String;
  final resultPort = message[2] as SendPort;

  try {
    final scanner = RustMusicScanner.tryLoad();
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

class PlaylistCoverIndexer {
  static const _batchSize = 12;
  static const _batchDelay = Duration(milliseconds: 140);
  static const _pauseDelay = Duration(milliseconds: 500);

  int _generation = 0;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _generation++;
  }

  void cancel() {
    _generation++;
  }

  Future<void> indexPlaylist({
    required List<Track> tracks,
    required LibraryDatabase database,
    required bool Function() shouldPause,
    required TrackCoverCacheUpdated onCacheUpdated,
  }) async {
    final generation = ++_generation;
    if (tracks.isEmpty) {
      return;
    }

    final cached = await database.loadTrackCoverCache(tracks);
    if (!_isCurrent(generation)) {
      return;
    }
    if (cached.isNotEmpty) {
      onCacheUpdated(cached);
    }

    final pending = tracks
        .where((track) => !cached.containsKey(track.path))
        .toList(growable: false);
    if (pending.isEmpty) {
      return;
    }

    final cacheDir = await coverCacheDir();
    for (var start = 0; start < pending.length; start += _batchSize) {
      while (_isCurrent(generation) && shouldPause()) {
        await Future<void>.delayed(_pauseDelay);
      }
      if (!_isCurrent(generation)) {
        return;
      }

      final batch = pending
          .skip(start)
          .take(_batchSize)
          .toList(growable: false);
      final extracted = await _extractBatch(
        batch.map((track) => track.path).toList(growable: false),
        cacheDir,
      );
      if (!_isCurrent(generation) || extracted.isEmpty) {
        return;
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
        return;
      }
      onCacheUpdated(updates);
      await Future<void>.delayed(_batchDelay);
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<Map<String, String?>> _extractBatch(
    List<String> paths,
    String cacheDir,
  ) async {
    final resultPort = ReceivePort();
    Isolate? worker;
    try {
      worker = await Isolate.spawn<List<Object?>>(_extractTrackCoverWorker, [
        paths,
        cacheDir,
        resultPort.sendPort,
      ]);
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
      worker?.kill(priority: Isolate.immediate);
      resultPort.close();
    }
  }
}
