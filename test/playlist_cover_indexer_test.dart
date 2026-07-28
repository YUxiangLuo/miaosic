import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_database.dart';
import 'package:miaosic/models.dart';
import 'package:miaosic/playlist_cover_indexer.dart';

void main() {
  test('indexes missing covers in batches and persists every result', () async {
    final fixture = await _IndexerFixture.create(batchSize: 2);
    addTearDown(fixture.close);
    final tracks = [
      _track('/music/1.flac', modifiedMs: 1),
      _track('/music/2.flac', modifiedMs: 2),
      _track('/music/3.flac', modifiedMs: 3),
    ];
    final updates = <String, String?>{};

    final completed = await fixture.indexer.indexTracks(
      tracks: tracks,
      database: fixture.database,
      knownCache: const {},
      shouldPause: () => false,
      onCacheUpdated: updates.addAll,
    );

    expect(completed, isTrue);
    expect(fixture.extractor.requests, [
      [tracks[0].path, tracks[1].path],
      [tracks[2].path],
    ]);
    expect(updates, {
      tracks[0].path: '${tracks[0].path}.jpg',
      tracks[1].path: '${tracks[1].path}.jpg',
      tracks[2].path: '${tracks[2].path}.jpg',
    });
    expect(await fixture.database.loadTrackCoverCache(tracks), updates);
    expect(fixture.extractor.closeCount, 1);
  });

  test(
    'cancellation discards an in-flight batch and closes the worker',
    () async {
      late final TrackCoverIndexer indexer;
      final fixture = await _IndexerFixture.create(
        onExtract: (_) {
          indexer.cancel();
        },
      );
      indexer = fixture.indexer;
      addTearDown(fixture.close);
      final track = _track('/music/cancel.flac');
      final updates = <String, String?>{};

      final completed = await indexer.indexTracks(
        tracks: [track],
        database: fixture.database,
        knownCache: const {},
        shouldPause: () => false,
        onCacheUpdated: updates.addAll,
      );

      expect(completed, isFalse);
      expect(updates, isEmpty);
      expect(await fixture.database.loadTrackCoverCache([track]), isEmpty);
      expect(fixture.extractor.closeCount, 1);
    },
  );

  test('waits while paused before extracting the next batch', () async {
    final fixture = await _IndexerFixture.create(
      pauseDelay: const Duration(milliseconds: 1),
    );
    addTearDown(fixture.close);
    final track = _track('/music/paused.flac');
    var pauseChecks = 0;

    final completed = await fixture.indexer.indexTracks(
      tracks: [track],
      database: fixture.database,
      knownCache: const {},
      shouldPause: () => pauseChecks++ < 2,
      onCacheUpdated: (_) {},
    );

    expect(completed, isTrue);
    expect(pauseChecks, 3);
    expect(fixture.extractor.requests.single, [track.path]);
  });

  test('closes the worker and propagates extraction failures', () async {
    final fixture = await _IndexerFixture.create(
      extractionError: StateError('extract failed'),
    );
    addTearDown(fixture.close);
    final track = _track('/music/failure.flac');

    await expectLater(
      fixture.indexer.indexTracks(
        tracks: [track],
        database: fixture.database,
        knownCache: const {},
        shouldPause: () => false,
        onCacheUpdated: (_) {},
      ),
      throwsA(isA<StateError>()),
    );

    expect(fixture.extractor.closeCount, 1);
    expect(await fixture.database.loadTrackCoverCache([track]), isEmpty);
  });
}

class _IndexerFixture {
  _IndexerFixture({
    required this.directory,
    required this.database,
    required this.extractor,
    required this.indexer,
  });

  final Directory directory;
  final LibraryDatabase database;
  final _FakeTrackCoverExtractor extractor;
  final TrackCoverIndexer indexer;

  static Future<_IndexerFixture> create({
    int batchSize = 24,
    Duration pauseDelay = Duration.zero,
    void Function(List<String> paths)? onExtract,
    Object? extractionError,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'miaosic_cover_indexer_test_',
    );
    final database = await LibraryDatabase.openAtPath(
      '${directory.path}/miaosic.db',
    );
    final extractor = _FakeTrackCoverExtractor(
      onExtract: onExtract,
      extractionError: extractionError,
    );
    final indexer = TrackCoverIndexer(
      startExtractor: (_) async => extractor,
      cacheDirectoryProvider: () async => directory.path,
      batchSize: batchSize,
      batchDelay: Duration.zero,
      pauseDelay: pauseDelay,
    );
    return _IndexerFixture(
      directory: directory,
      database: database,
      extractor: extractor,
      indexer: indexer,
    );
  }

  Future<void> close() async {
    indexer.dispose();
    await database.close();
    await directory.delete(recursive: true);
  }
}

class _FakeTrackCoverExtractor implements TrackCoverExtractor {
  _FakeTrackCoverExtractor({this.onExtract, this.extractionError});

  final void Function(List<String> paths)? onExtract;
  final Object? extractionError;
  final List<List<String>> requests = [];
  int closeCount = 0;

  @override
  Future<Map<String, String?>> extract(List<String> paths) async {
    requests.add(List.unmodifiable(paths));
    onExtract?.call(paths);
    final error = extractionError;
    if (error != null) {
      throw error;
    }
    return {for (final path in paths) path: '$path.jpg'};
  }

  @override
  void close() {
    closeCount += 1;
  }
}

Track _track(String path, {int modifiedMs = 1}) {
  return Track(
    path: path,
    folderPath: '/music',
    title: path.split('/').last,
    artist: 'Artist',
    album: 'Album',
    albumArtist: 'Artist',
    trackNumber: 1,
    discNumber: null,
    year: 2026,
    durationMs: 120000,
    sizeBytes: 42,
    modifiedMs: modifiedMs,
    coverArtPath: null,
  );
}
