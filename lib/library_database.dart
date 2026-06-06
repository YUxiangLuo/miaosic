import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await _createSchema(db);
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
      batch.insert('scan_state', {
        'root_path': result.rootPath,
        'track_count': result.tracks.length,
        'folder_count': result.folders.length,
        'album_count': result.albums.length,
        'scanned_at_ms': DateTime.now().millisecondsSinceEpoch,
        'elapsed_ms': result.elapsed.inMilliseconds,
      });
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
        modified_ms INTEGER NOT NULL
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
        year_count INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_folders_kind ON folders(kind)');

    await db.execute('''
      CREATE TABLE albums (
        folder_path TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        album_artist TEXT NOT NULL,
        year INTEGER,
        track_count INTEGER NOT NULL
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
        elapsed_ms INTEGER NOT NULL
      )
    ''');
  }
}
