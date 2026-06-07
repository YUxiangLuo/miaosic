import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_controller.dart';
import 'package:miaosic/library_database.dart';
import 'package:miaosic/models.dart';
import 'package:miaosic/music_scanner.dart';
import 'package:miaosic/playlist_cover_indexer.dart';

void main() {
  test('opens an empty database and scans the configured music root', () async {
    final dir = await Directory.systemTemp.createTemp(
      'miaosic_controller_test_',
    );
    final dbPath = '${dir.path}/miaosic.db';
    final seedDatabase = await LibraryDatabase.openAtPath(dbPath);
    await seedDatabase.saveMusicRoot('/music/root');
    await seedDatabase.close();

    final controller = LibraryController(
      openDatabase: () => LibraryDatabase.openAtPath(dbPath),
      scanner: _FakeMusicScanner((
        rootPath, {
        onProgress,
        previousTracks,
      }) async {
        expect(rootPath, '/music/root');
        expect(previousTracks, isNull);
        onProgress?.call(
          const ScanProgress(
            filesSeen: 1,
            tracksParsed: 1,
            currentPath: '/music/root/a.flac',
          ),
        );
        return _scanResult([_track('/music/root/a.flac')]);
      }),
      coverIndexer: _NoopTrackCoverIndexer(),
    );

    try {
      await controller.open();

      expect(controller.loading, isFalse);
      expect(controller.scanning, isFalse);
      expect(controller.musicRoot, '/music/root');
      expect(controller.tracks.single.path, '/music/root/a.flac');

      final reopened = await LibraryDatabase.openAtPath(dbPath);
      addTearDown(reopened.close);
      expect((await reopened.loadTracks()).single.path, '/music/root/a.flac');
    } finally {
      controller.dispose();
      await dir.delete(recursive: true);
    }
  });
}

typedef _ScanHandler =
    Future<ScanResult> Function(
      String rootPath, {
      ScanProgressCallback? onProgress,
      List<Track>? previousTracks,
    });

class _FakeMusicScanner extends MusicScanner {
  _FakeMusicScanner(this._handler) : super(rustScannerLoader: () => null);

  final _ScanHandler _handler;

  @override
  Future<ScanResult> scan(
    String rootPath, {
    ScanProgressCallback? onProgress,
    List<Track>? previousTracks,
  }) {
    return _handler(
      rootPath,
      onProgress: onProgress,
      previousTracks: previousTracks,
    );
  }
}

class _NoopTrackCoverIndexer extends TrackCoverIndexer {
  @override
  Future<bool> indexTracks({
    required List<Track> tracks,
    required LibraryDatabase database,
    Map<String, String?>? knownCache,
    required bool Function() shouldPause,
    required TrackCoverCacheUpdated onCacheUpdated,
  }) async {
    return true;
  }
}

ScanResult _scanResult(List<Track> tracks) {
  return ScanResult(
    rootPath: '/music/root',
    engine: 'test',
    tracks: tracks,
    folders: const [],
    albums: const [],
    elapsed: Duration.zero,
    coversCached: 0,
  );
}

Track _track(String path) {
  return Track(
    path: path,
    folderPath: '/music/root',
    title: 'A',
    artist: 'Artist',
    album: 'Album',
    albumArtist: 'Artist',
    trackNumber: 1,
    discNumber: null,
    year: null,
    durationMs: null,
    sizeBytes: 1,
    modifiedMs: 1,
    coverArtPath: null,
  );
}
