import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'library_diff.dart';
import 'models.dart';

class LibraryDatabase {
  LibraryDatabase._(this._db, this.path);

  final Database _db;
  final String path;

  static Future<LibraryDatabase> open() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final appDir = await getApplicationSupportDirectory();
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    final dbPath = p.join(appDir.path, 'miaosic.db');
    return openAtPath(dbPath);
  }

  static Future<LibraryDatabase> openAtPath(String dbPath) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _upgradeToV2(db);
          }
        },
      ),
    );
    return LibraryDatabase._(db, dbPath);
  }

  Future<void> close() => _db.close();

  Future<List<Track>> loadTracks() async {
    final rows = await _db.query(
      'tracks',
      orderBy:
          'folder_path COLLATE NOCASE, disc_number, track_number, title COLLATE NOCASE',
    );
    return rows.map(Track.fromMap).toList();
  }

  Future<List<FolderSummary>> loadFolders() async {
    final rows = await _db.query(
      'folders',
      orderBy: 'kind COLLATE NOCASE, name COLLATE NOCASE',
    );
    return rows.map(FolderSummary.fromMap).toList();
  }

  Future<List<AlbumSummary>> loadAlbums() async {
    final rows = await _db.query(
      'albums',
      orderBy: 'album_artist COLLATE NOCASE, year, title COLLATE NOCASE',
    );
    return rows.map(AlbumSummary.fromMap).toList();
  }

  Future<void> replaceLibrary(ScanResult result) async {
    await _db.transaction((txn) async {
      await txn.delete('tracks');
      await txn.delete('folders');
      await txn.delete('albums');
      await txn.delete('scan_state');

      final batch = txn.batch();
      for (final track in result.tracks) {
        batch.insert('tracks', track.toMap());
      }
      for (final folder in result.folders) {
        batch.insert('folders', folder.toMap());
      }
      for (final album in result.albums) {
        batch.insert('albums', album.toMap());
      }
      batch.insert('scan_state', _scanStateMap(result));
      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, Object?>?> loadScanState() async {
    final rows = await _db.query('scan_state', limit: 1);
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<LibrarySnapshot> loadSnapshot() async {
    return LibrarySnapshot(
      tracks: await loadTracks(),
      folders: await loadFolders(),
      albums: await loadAlbums(),
      scanState: await loadScanState(),
    );
  }

  Future<void> applyDiff(LibraryDiff diff) async {
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final change in diff.removed) {
        batch.delete('tracks', where: 'path = ?', whereArgs: [change.path]);
      }
      for (final change in diff.added) {
        final track = change.newTrack;
        if (track != null) {
          batch.insert('tracks', track.toMap()..remove('id'));
        }
      }
      for (final change in diff.modified) {
        final track = change.newTrack;
        if (track != null) {
          final values = track.toMap()
            ..remove('id')
            ..remove('path');
          batch.update(
            'tracks',
            values,
            where: 'path = ?',
            whereArgs: [track.path],
          );
        }
      }

      batch.delete('folders');
      batch.delete('albums');
      batch.delete('scan_state');
      for (final folder in diff.result.folders) {
        batch.insert('folders', folder.toMap());
      }
      for (final album in diff.result.albums) {
        batch.insert('albums', album.toMap());
      }
      batch.insert('scan_state', _scanStateMap(diff.result));
      await batch.commit(noResult: true);
    });
  }

  static Future<void> _createSchema(Database db) async {
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
        modified_ms INTEGER NOT NULL,
        cover_art_path TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_tracks_folder ON tracks(folder_path)');
    await db.execute(
      'CREATE INDEX idx_tracks_title ON tracks(title COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE INDEX idx_tracks_artist ON tracks(artist COLLATE NOCASE)',
    );

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
        year_count INTEGER NOT NULL,
        cover_art_path TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_folders_kind ON folders(kind)');

    await db.execute('''
      CREATE TABLE albums (
        folder_path TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        album_artist TEXT NOT NULL,
        year INTEGER,
        track_count INTEGER NOT NULL,
        cover_art_path TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_albums_artist ON albums(album_artist COLLATE NOCASE)',
    );

    await db.execute('''
      CREATE TABLE scan_state (
        root_path TEXT PRIMARY KEY,
        track_count INTEGER NOT NULL,
        folder_count INTEGER NOT NULL,
        album_count INTEGER NOT NULL,
        scanned_at_ms INTEGER NOT NULL,
        elapsed_ms INTEGER NOT NULL,
        cover_cache_version INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  static Future<void> _upgradeToV2(Database db) async {
    await _addColumnIfMissing(db, 'tracks', 'cover_art_path TEXT');
    await _addColumnIfMissing(db, 'folders', 'cover_art_path TEXT');
    await _addColumnIfMissing(db, 'albums', 'cover_art_path TEXT');
    await _addColumnIfMissing(
      db,
      'scan_state',
      'cover_cache_version INTEGER NOT NULL DEFAULT 0',
    );
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String definition,
  ) async {
    final column = definition.split(' ').first;
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final exists = rows.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $definition');
    }
  }

  static Map<String, Object?> _scanStateMap(ScanResult result) {
    return {
      'root_path': result.rootPath,
      'track_count': result.tracks.length,
      'folder_count': result.folders.length,
      'album_count': result.albums.length,
      'scanned_at_ms': DateTime.now().millisecondsSinceEpoch,
      'elapsed_ms': result.elapsed.inMilliseconds,
      'cover_cache_version': 1,
    };
  }
}
