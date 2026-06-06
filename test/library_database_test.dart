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
    await upgraded.close();
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

ScanResult _scanResult(List<Track> tracks) {
  return ScanResult(
    rootPath: '/music',
    engine: 'test',
    tracks: tracks,
    folders: const [],
    albums: const [],
    elapsed: Duration.zero,
    coversCached: 0,
  );
}

Track _track(String path, {required int size, required int modified}) {
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
    coverArtPath: null,
  );
}
