import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_controller.dart';
import 'package:miaosic/library_database.dart';
import 'package:miaosic/library_types.dart';
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
    await seedDatabase.saveThemeMode('dark');
    const lastPlayback = LastPlaybackState(
      kind: LastPlaybackKind.album,
      folderPath: '/music/root',
      trackPath: '/music/root/a.flac',
      playing: true,
      shuffled: false,
    );
    await seedDatabase.saveLastPlayback(lastPlayback);
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
      expect(controller.settingsLoaded, isFalse);
      await controller.open();

      expect(controller.loading, isFalse);
      expect(controller.settingsLoaded, isTrue);
      expect(controller.scanning, isFalse);
      expect(controller.musicRoot, '/music/root');
      expect(controller.themeMode, 'dark');
      expect(controller.tracks.single.path, '/music/root/a.flac');
      expect(controller.lastPlayback?.kind, LastPlaybackKind.album);
      expect(controller.lastPlayback?.folderPath, lastPlayback.folderPath);
      expect(controller.lastPlayback?.trackPath, lastPlayback.trackPath);
      expect(controller.lastPlayback?.playing, isTrue);
      expect(controller.lastPlayback?.shuffled, isFalse);
      await controller.saveThemeMode('light');
      expect(controller.themeMode, 'light');

      final reopened = await LibraryDatabase.openAtPath(dbPath);
      addTearDown(reopened.close);
      expect((await reopened.loadTracks()).single.path, '/music/root/a.flac');
      expect(await reopened.loadThemeMode(), 'light');
    } finally {
      controller.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('rescan refreshes folder metadata when tracks are unchanged', () async {
    final dir = await Directory.systemTemp.createTemp(
      'miaosic_controller_rescan_metadata_test_',
    );
    final dbPath = '${dir.path}/miaosic.db';
    final track = _track('/music/root/Maroon 5 Essentials/01.flac');
    final seedDatabase = await LibraryDatabase.openAtPath(dbPath);
    await seedDatabase.saveMusicRoot('/music/root');
    await seedDatabase.replaceLibrary(
      _scanResult(
        [track],
        folders: [_folder('/music/root/Maroon 5 Essentials')],
      ),
    );
    await seedDatabase.close();

    final controller = LibraryController(
      openDatabase: () => LibraryDatabase.openAtPath(dbPath),
      scanner: _FakeMusicScanner((
        rootPath, {
        onProgress,
        previousTracks,
      }) async {
        expect(rootPath, '/music/root');
        expect(previousTracks?.map((track) => track.path), [track.path]);
        return _scanResult(
          [track],
          folders: [
            _folder(
              '/music/root/Maroon 5 Essentials',
              kind: FolderKind.playlist,
            ),
          ],
        );
      }),
      coverIndexer: _NoopTrackCoverIndexer(),
    );

    try {
      await controller.open();
      expect(controller.playlistFolders, isEmpty);

      controller.startRescanDiff();
      await _waitForRescanReady(controller);

      expect(controller.rescanState.value.diff?.hasChanges, isFalse);
      expect(controller.playlistFolders.single.kind, FolderKind.playlist);

      final reopened = await LibraryDatabase.openAtPath(dbPath);
      addTearDown(reopened.close);
      expect((await reopened.loadFolders()).single.kind, FolderKind.playlist);
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
    // Avoid reporting completion in tests because LibraryController prunes the
    // real app cover cache after a completed background index pass.
    return false;
  }
}

ScanResult _scanResult(
  List<Track> tracks, {
  List<FolderSummary> folders = const [],
}) {
  return ScanResult(
    rootPath: '/music/root',
    engine: 'test',
    tracks: tracks,
    folders: folders,
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

FolderSummary _folder(String path, {FolderKind kind = FolderKind.album}) {
  return FolderSummary(
    path: path,
    name: 'Maroon 5 Essentials',
    kind: kind,
    confidence: 0.75,
    trackCount: 1,
    albumCount: 1,
    albumArtistCount: 1,
    artistCount: 1,
    yearCount: 1,
    coverArtPath: null,
  );
}

Future<void> _waitForRescanReady(LibraryController controller) async {
  for (var i = 0; i < 100; i++) {
    if (controller.rescanState.value.phase == RescanPhase.ready) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for rescan ready. '
    'phase=${controller.rescanState.value.phase} '
    'error=${controller.rescanState.value.error}',
  );
}
