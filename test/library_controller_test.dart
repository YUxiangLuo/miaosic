import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/audio_output_settings.dart';
import 'package:miaosic/library_controller.dart';
import 'package:miaosic/library_database.dart';
import 'package:miaosic/library_diff.dart';
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
    await seedDatabase.saveAudioOutputSettings(
      const AudioOutputSettings(
        deviceName: 'pipewire/dac',
        deviceDescription: 'USB DAC',
      ),
    );
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
      expect(controller.audioOutputSettings.deviceName, 'pipewire/dac');
      expect(controller.audioOutputSettings.deviceDescription, 'USB DAC');
      expect(controller.tracks.single.path, '/music/root/a.flac');
      expect(controller.rescanState.value.mode, LibraryScanMode.direct);
      expect(controller.rescanState.value.phase, RescanPhase.done);
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

  test('applying pending diff clears the applied diff state', () async {
    final dir = await Directory.systemTemp.createTemp(
      'miaosic_controller_apply_diff_test_',
    );
    final dbPath = '${dir.path}/miaosic.db';
    final track = _track('/music/root/a.flac');
    final seedDatabase = await LibraryDatabase.openAtPath(dbPath);
    await seedDatabase.saveMusicRoot('/music/root');
    await seedDatabase.replaceLibrary(_scanResult([track]));
    await seedDatabase.close();

    final controller = LibraryController(
      openDatabase: () => LibraryDatabase.openAtPath(dbPath),
      scanner: _FakeMusicScanner((
        rootPath, {
        onProgress,
        previousTracks,
      }) async {
        fail('open should load the seeded library without scanning');
      }),
      coverIndexer: _NoopTrackCoverIndexer(),
    );

    try {
      await controller.open();
      final diff = _diff(hasChanges: true);
      controller.rescanState.value = RescanUiState(
        phase: RescanPhase.ready,
        diff: diff,
      );

      final applied = await controller.applyPendingDiff(
        confirmLargeDeletion: (_) async => true,
      );

      expect(applied, same(diff));
      expect(controller.rescanState.value.mode, LibraryScanMode.diff);
      expect(controller.rescanState.value.phase, RescanPhase.done);
      expect(controller.rescanState.value.message, 'Library refreshed');
      expect(controller.rescanState.value.diff, isNull);

      controller.prepareRescanDialog();
      expect(controller.rescanState.value.phase, RescanPhase.idle);
      expect(controller.rescanState.value.diff, isNull);
    } finally {
      controller.dispose();
      await dir.delete(recursive: true);
    }
  });

  test(
    'changing music root scans immediately and clears pending diff',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'miaosic_controller_change_root_test_',
      );
      final oldRoot = Directory('${dir.path}/old');
      final newRoot = Directory('${dir.path}/new');
      await oldRoot.create();
      await newRoot.create();
      final dbPath = '${dir.path}/miaosic.db';
      final oldTrack = _track('${oldRoot.path}/old.flac');
      final newTrack = _track('${newRoot.path}/new.flac');
      const oldPlayback = LastPlaybackState(
        kind: LastPlaybackKind.album,
        folderPath: '/old/album',
        trackPath: '/old/album/old.flac',
        playing: true,
        shuffled: false,
      );

      final seedDatabase = await LibraryDatabase.openAtPath(dbPath);
      await seedDatabase.saveMusicRoot(oldRoot.path);
      await seedDatabase.saveLastPlayback(oldPlayback);
      await seedDatabase.replaceLibrary(
        _scanResult([oldTrack], rootPath: oldRoot.path),
      );
      await seedDatabase.saveTrackCoverCache([
        TrackCoverCacheEntry(
          path: oldTrack.path,
          sizeBytes: oldTrack.sizeBytes,
          modifiedMs: oldTrack.modifiedMs,
          coverArtPath: '/cache/old.jpg',
        ),
      ]);
      await seedDatabase.close();

      late final LibraryController controller;
      controller = LibraryController(
        openDatabase: () => LibraryDatabase.openAtPath(dbPath),
        scanner: _FakeMusicScanner((
          rootPath, {
          onProgress,
          previousTracks,
        }) async {
          if (rootPath == oldRoot.path) {
            return _scanResult([oldTrack], rootPath: oldRoot.path);
          }
          expect(rootPath, newRoot.path);
          expect(previousTracks, isNull);
          expect(controller.tracks, isEmpty);
          expect(controller.folders, isEmpty);
          expect(controller.albums, isEmpty);
          expect(controller.lastPlayback, isNull);
          expect(controller.trackCoverCache, isEmpty);
          onProgress?.call(
            ScanProgress(
              filesSeen: 1,
              tracksParsed: 1,
              currentPath: newTrack.path,
            ),
          );
          expect(controller.rescanState.value.mode, LibraryScanMode.direct);
          expect(controller.rescanState.value.phase, RescanPhase.scanning);
          expect(controller.rescanState.value.diff, isNull);
          return _scanResult([newTrack], rootPath: newRoot.path);
        }),
        coverIndexer: _NoopTrackCoverIndexer(),
      );

      try {
        await controller.open();
        expect(controller.tracks.single.path, oldTrack.path);
        expect(controller.lastPlayback?.trackPath, oldPlayback.trackPath);
        controller.rescanState.value = RescanUiState(
          phase: RescanPhase.ready,
          diff: _diff(hasChanges: true, rootPath: oldRoot.path),
        );

        final changed = await controller.changeMusicRoot(newRoot.path);

        expect(changed, isTrue);
        expect(controller.musicRoot, newRoot.path);
        expect(controller.tracks.single.path, newTrack.path);
        expect(controller.rescanState.value.mode, LibraryScanMode.direct);
        expect(controller.rescanState.value.phase, RescanPhase.done);
        expect(controller.rescanState.value.diff, isNull);
        expect(controller.rescanState.value.progress, isNull);
        expect(controller.scanning, isFalse);

        final applied = await controller.applyPendingDiff(
          confirmLargeDeletion: (_) async => true,
        );
        expect(applied, isNull);

        controller.prepareRescanDialog();
        expect(controller.rescanState.value.mode, LibraryScanMode.diff);
        expect(controller.rescanState.value.phase, RescanPhase.idle);

        final reopened = await LibraryDatabase.openAtPath(dbPath);
        addTearDown(reopened.close);
        expect(await reopened.loadMusicRoot(), newRoot.path);
        expect((await reopened.loadTracks()).single.path, newTrack.path);
        expect(await reopened.loadLastPlayback(), isNull);
        expect(await reopened.loadTrackCoverCache([oldTrack]), isEmpty);
      } finally {
        controller.dispose();
        await dir.delete(recursive: true);
      }
    },
  );

  test('changing music root still succeeds when the new scan fails', () async {
    final dir = await Directory.systemTemp.createTemp(
      'miaosic_controller_change_root_failure_test_',
    );
    final oldRoot = Directory('${dir.path}/old');
    final newRoot = Directory('${dir.path}/new');
    await oldRoot.create();
    await newRoot.create();
    final dbPath = '${dir.path}/miaosic.db';
    final oldTrack = _track('${oldRoot.path}/old.flac');

    final seedDatabase = await LibraryDatabase.openAtPath(dbPath);
    await seedDatabase.saveMusicRoot(oldRoot.path);
    await seedDatabase.saveLastPlayback(
      LastPlaybackState(
        kind: LastPlaybackKind.album,
        folderPath: oldRoot.path,
        trackPath: oldTrack.path,
        playing: true,
        shuffled: false,
      ),
    );
    await seedDatabase.replaceLibrary(
      _scanResult([oldTrack], rootPath: oldRoot.path),
    );
    await seedDatabase.close();

    final controller = LibraryController(
      openDatabase: () => LibraryDatabase.openAtPath(dbPath),
      scanner: _FakeMusicScanner((
        rootPath, {
        onProgress,
        previousTracks,
      }) async {
        if (rootPath == oldRoot.path) {
          return _scanResult([oldTrack], rootPath: oldRoot.path);
        }
        expect(rootPath, newRoot.path);
        expect(previousTracks, isNull);
        throw StateError('scan failed');
      }),
      coverIndexer: _NoopTrackCoverIndexer(),
    );

    try {
      await controller.open();

      final changed = await controller.changeMusicRoot(newRoot.path);

      expect(changed, isTrue);
      expect(controller.musicRoot, newRoot.path);
      expect(controller.tracks, isEmpty);
      expect(controller.lastPlayback, isNull);
      expect(controller.rescanState.value.mode, LibraryScanMode.direct);
      expect(controller.rescanState.value.phase, RescanPhase.error);
      expect(controller.error, contains('scan failed'));

      final reopened = await LibraryDatabase.openAtPath(dbPath);
      addTearDown(reopened.close);
      expect(await reopened.loadMusicRoot(), newRoot.path);
      expect(await reopened.loadTracks(), isEmpty);
      expect(await reopened.loadLastPlayback(), isNull);
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
  String rootPath = '/music/root',
}) {
  return ScanResult(
    rootPath: rootPath,
    engine: 'test',
    tracks: tracks,
    folders: folders,
    albums: const [],
    elapsed: Duration.zero,
    coversCached: 0,
  );
}

LibraryDiff _diff({required bool hasChanges, String rootPath = '/music/root'}) {
  final track = _track('$rootPath/diff.flac');
  return LibraryDiff(
    added: hasChanges
        ? [
            TrackChange(
              path: track.path,
              oldTrack: null,
              newTrack: track,
              reason: TrackChangeReason.added,
            ),
          ]
        : const [],
    removed: const [],
    modified: const [],
    unchangedCount: hasChanges ? 0 : 1,
    result: _scanResult([if (hasChanges) track], rootPath: rootPath),
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
