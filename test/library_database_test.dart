import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaosic/library_database.dart';
import 'package:miaosic/library_diff.dart';
import 'package:miaosic/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('upgrades v1 schema with cover art columns', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dir = await Directory.systemTemp.createTemp('miaosic_db_test_');
    final dbPath = '${dir.path}/miaosic.db';
    final v1 = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await _createV1Schema(db);
        },
      ),
    );
    await v1.close();

    final database = await LibraryDatabase.openAtPath(dbPath);
    await database.close();

    final upgraded = await databaseFactory.openDatabase(dbPath);
    expect(await _columns(upgraded, 'tracks'), contains('cover_art_path'));
    expect(await _columns(upgraded, 'folders'), contains('cover_art_path'));
    expect(await _columns(upgraded, 'albums'), contains('cover_art_path'));
    expect(
      await _columns(upgraded, 'scan_state'),
      contains('cover_cache_version'),
    );
    expect(await _tables(upgraded), contains('track_cover_cache'));
    expect(await _tables(upgraded), contains('settings'));
    await upgraded.close();
    await dir.delete(recursive: true);
  });

  test('persists configurable music root', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dir = await Directory.systemTemp.createTemp('miaosic_settings_test_');
    final dbPath = '${dir.path}/miaosic.db';
    final database = await LibraryDatabase.openAtPath(dbPath);

    expect(await database.loadMusicRoot(), defaultMusicRoot);

    await database.saveMusicRoot('/music/custom');
    expect(await database.loadMusicRoot(), '/music/custom');

    await database.close();
    final reopened = await LibraryDatabase.openAtPath(dbPath);
    expect(await reopened.loadMusicRoot(), '/music/custom');

    await reopened.close();
    await dir.delete(recursive: true);
  });

  test('persists last playback state', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dir = await Directory.systemTemp.createTemp(
      'miaosic_last_playback_test_',
    );
    final dbPath = '${dir.path}/miaosic.db';
    final database = await LibraryDatabase.openAtPath(dbPath);

    expect(await database.loadLastPlayback(), isNull);

    const state = LastPlaybackState(
      kind: LastPlaybackKind.playlist,
      folderPath: '/music/playlists/favorites',
      trackPath: '/music/playlists/favorites/02.flac',
      playing: true,
    );
    await database.saveLastPlayback(state);

    final loaded = await database.loadLastPlayback();
    expect(loaded?.kind, LastPlaybackKind.playlist);
    expect(loaded?.folderPath, state.folderPath);
    expect(loaded?.trackPath, state.trackPath);
    expect(loaded?.playing, isTrue);

    await database.close();
    final reopened = await LibraryDatabase.openAtPath(dbPath);
    final reloaded = await reopened.loadLastPlayback();
    expect(reloaded?.kind, LastPlaybackKind.playlist);
    expect(reloaded?.folderPath, state.folderPath);
    expect(reloaded?.trackPath, state.trackPath);
    expect(reloaded?.playing, isTrue);

    await reopened.close();
    await dir.delete(recursive: true);
  });

  test('defaults legacy last playback records to not playing', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dir = await Directory.systemTemp.createTemp(
      'miaosic_legacy_last_playback_test_',
    );
    final dbPath = '${dir.path}/miaosic.db';
    final database = await LibraryDatabase.openAtPath(dbPath);
    await database.close();

    final raw = await databaseFactory.openDatabase(dbPath);
    await raw.insert('settings', {
      'key': LibraryDatabase.lastPlaybackSettingKey,
      'value':
          '{"kind":"album","folder_path":"/music/album","track_path":"/music/album/01.flac"}',
    });
    await raw.close();

    final reopened = await LibraryDatabase.openAtPath(dbPath);
    final loaded = await reopened.loadLastPlayback();
    expect(loaded?.kind, LastPlaybackKind.album);
    expect(loaded?.folderPath, '/music/album');
    expect(loaded?.trackPath, '/music/album/01.flac');
    expect(loaded?.playing, isFalse);

    await reopened.close();
    await dir.delete(recursive: true);
  });

  test('applies diff without rewriting unchanged tracks', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dir = await Directory.systemTemp.createTemp('miaosic_db_apply_test_');
    final dbPath = '${dir.path}/miaosic.db';
    final database = await LibraryDatabase.openAtPath(dbPath);
    final unchanged = _track('/music/a.flac', size: 10, modified: 1);
    final changedOld = _track('/music/b.flac', size: 10, modified: 1);
    final removed = _track('/music/c.flac', size: 10, modified: 1);
    await database.replaceLibrary(
      _scanResult([unchanged, changedOld, removed]),
    );

    final before = await database.loadTracks();
    final unchangedId = before
        .firstWhere((track) => track.path == unchanged.path)
        .id;
    final changedNew = _track('/music/b.flac', size: 11, modified: 1);
    final added = _track('/music/d.flac', size: 10, modified: 1);
    final snapshot = await database.loadSnapshot();
    final diff = diffLibrary(
      snapshot,
      _scanResult([unchanged, changedNew, added]),
    );
    await database.applyDiff(diff);

    final after = await database.loadTracks();
    expect(
      after.map((track) => track.path),
      containsAll(['/music/a.flac', '/music/b.flac', '/music/d.flac']),
    );
    expect(after.map((track) => track.path), isNot(contains('/music/c.flac')));
    expect(
      after.firstWhere((track) => track.path == unchanged.path).id,
      unchangedId,
    );
    expect(
      after.firstWhere((track) => track.path == changedNew.path).sizeBytes,
      11,
    );

    await database.close();
    await dir.delete(recursive: true);
  });

  test('updates scan state without replacing unchanged tracks', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dir = await Directory.systemTemp.createTemp(
      'miaosic_scan_state_test_',
    );
    final dbPath = '${dir.path}/miaosic.db';
    final database = await LibraryDatabase.openAtPath(dbPath);
    final unchanged = _track('/music/a.flac', size: 10, modified: 1);
    await database.replaceLibrary(
      _scanResult([unchanged], elapsed: const Duration(seconds: 37)),
    );
    final unchangedId = (await database.loadTracks()).single.id;

    await database.saveScanState(
      _scanResult([unchanged], elapsed: const Duration(milliseconds: 25)),
    );

    final scanState = await database.loadScanState();
    expect(scanState?['elapsed_ms'], 25);
    expect((await database.loadTracks()).single.id, unchangedId);

    await database.close();
    await dir.delete(recursive: true);
  });

  test('loads only valid track cover cache entries', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dir = await Directory.systemTemp.createTemp('miaosic_cover_test_');
    final dbPath = '${dir.path}/miaosic.db';
    final database = await LibraryDatabase.openAtPath(dbPath);
    final valid = _track('/music/a.flac', size: 10, modified: 1);
    final checkedMissing = _track('/music/b.flac', size: 11, modified: 1);
    final changed = _track('/music/c.flac', size: 12, modified: 1);

    await database.saveTrackCoverCache([
      TrackCoverCacheEntry(
        path: valid.path,
        sizeBytes: valid.sizeBytes,
        modifiedMs: valid.modifiedMs,
        coverArtPath: '/cache/a.jpg',
      ),
      TrackCoverCacheEntry(
        path: checkedMissing.path,
        sizeBytes: checkedMissing.sizeBytes,
        modifiedMs: checkedMissing.modifiedMs,
        coverArtPath: null,
      ),
      TrackCoverCacheEntry(
        path: changed.path,
        sizeBytes: changed.sizeBytes,
        modifiedMs: changed.modifiedMs + 1,
        coverArtPath: '/cache/stale.jpg',
      ),
    ]);

    final cached = await database.loadTrackCoverCache([
      valid,
      checkedMissing,
      changed,
    ]);

    expect(cached[valid.path], '/cache/a.jpg');
    expect(cached.containsKey(checkedMissing.path), isTrue);
    expect(cached[checkedMissing.path], isNull);
    expect(cached.containsKey(changed.path), isFalse);

    await database.close();
    await dir.delete(recursive: true);
  });

  test('loads referenced cover art paths from current library state', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dir = await Directory.systemTemp.createTemp(
      'miaosic_cover_refs_test_',
    );
    final dbPath = '${dir.path}/miaosic.db';
    final database = await LibraryDatabase.openAtPath(dbPath);
    final valid = _track(
      '/music/a.flac',
      size: 10,
      modified: 1,
      cover: '/cache/folder.jpg',
    );
    final changed = _track('/music/b.flac', size: 12, modified: 1);
    await database.replaceLibrary(_scanResult([valid, changed]));
    await database.saveTrackCoverCache([
      TrackCoverCacheEntry(
        path: valid.path,
        sizeBytes: valid.sizeBytes,
        modifiedMs: valid.modifiedMs,
        coverArtPath: '/cache/track.jpg',
      ),
      TrackCoverCacheEntry(
        path: changed.path,
        sizeBytes: changed.sizeBytes,
        modifiedMs: changed.modifiedMs + 1,
        coverArtPath: '/cache/stale.jpg',
      ),
    ]);

    final referenced = await database.loadReferencedCoverArtPaths();

    expect(referenced, containsAll(['/cache/folder.jpg', '/cache/track.jpg']));
    expect(referenced, isNot(contains('/cache/stale.jpg')));

    await database.close();
    await dir.delete(recursive: true);
  });
}

Future<void> _createV1Schema(Database db) async {
  await db.execute('''
    CREATE TABLE tracks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      path TEXT NOT NULL UNIQUE,
      folder_path TEXT NOT NULL,
      title TEXT NOT NULL,
      artist TEXT NOT NULL,
      album TEXT NOT NULL,
      album_artist TEXT NOT NULL,
      track_number INTEGER,
      disc_number INTEGER,
      year INTEGER,
      duration_ms INTEGER,
      size_bytes INTEGER NOT NULL,
      modified_ms INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE folders (
      path TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      kind TEXT NOT NULL,
      confidence REAL NOT NULL,
      track_count INTEGER NOT NULL,
      album_count INTEGER NOT NULL,
      album_artist_count INTEGER NOT NULL,
      artist_count INTEGER NOT NULL,
      year_count INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE albums (
      folder_path TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      album_artist TEXT NOT NULL,
      year INTEGER,
      track_count INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE scan_state (
      root_path TEXT PRIMARY KEY,
      track_count INTEGER NOT NULL,
      folder_count INTEGER NOT NULL,
      album_count INTEGER NOT NULL,
      scanned_at_ms INTEGER NOT NULL,
      elapsed_ms INTEGER NOT NULL
    )
  ''');
}

Future<Set<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'] as String).toSet();
}

Future<Set<String>> _tables(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((row) => row['name'] as String).toSet();
}

ScanResult _scanResult(List<Track> tracks, {Duration elapsed = Duration.zero}) {
  return ScanResult(
    rootPath: '/music',
    engine: 'test',
    tracks: tracks,
    folders: const [],
    albums: const [],
    elapsed: elapsed,
    coversCached: 0,
  );
}

Track _track(
  String path, {
  required int size,
  required int modified,
  String? cover,
}) {
  return Track(
    path: path,
    folderPath: '/music',
    title: path,
    artist: 'Artist',
    album: 'Album',
    albumArtist: 'Artist',
    trackNumber: null,
    discNumber: null,
    year: null,
    durationMs: null,
    sizeBytes: size,
    modifiedMs: modified,
    coverArtPath: cover,
  );
}
