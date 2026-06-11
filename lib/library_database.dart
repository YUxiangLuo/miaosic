import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'audio_output_settings.dart';
import 'library_diff.dart';
import 'llm_settings.dart';
import 'models.dart';

class LibraryDatabase {
  LibraryDatabase._(this._db, this.path);

  static const musicRootSettingKey = 'music_root';
  static const lastPlaybackSettingKey = 'last_playback';
  static const llmSettingsSettingKey = 'llm_settings';
  static const themeModeSettingKey = 'theme_mode';
  static const audioOutputSettingsSettingKey = 'audio_output_settings';

  final Database _db;
  final String path;

  static Future<LibraryDatabase> open() async {
    sqfliteFfiInit();

    final appDir = await getApplicationSupportDirectory();
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    final dbPath = p.join(appDir.path, 'miaosic.db');
    return openAtPath(dbPath);
  }

  static Future<LibraryDatabase> openAtPath(String dbPath) async {
    sqfliteFfiInit();

    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _upgradeToV2(db);
          }
          if (oldVersion < 3) {
            await _upgradeToV3(db);
          }
          if (oldVersion < 4) {
            await _upgradeToV4(db);
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

  Future<Map<String, String?>> loadTrackCoverCache(List<Track> tracks) async {
    if (tracks.isEmpty) {
      return const {};
    }

    final tracksByPath = {for (final track in tracks) track.path: track};
    final cached = <String, String?>{};
    final paths = tracksByPath.keys.toList();
    for (var start = 0; start < paths.length; start += 450) {
      final chunk = paths.skip(start).take(450).toList();
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await _db.query(
        'track_cover_cache',
        where: 'path IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final row in rows) {
        final path = row['path'] as String;
        final track = tracksByPath[path];
        if (track == null) {
          continue;
        }
        if (row['size_bytes'] == track.sizeBytes &&
            row['modified_ms'] == track.modifiedMs) {
          cached[path] = row['cover_art_path'] as String?;
        }
      }
    }
    return cached;
  }

  Future<void> saveTrackCoverCache(
    Iterable<TrackCoverCacheEntry> entries,
  ) async {
    final batch = _db.batch();
    for (final entry in entries) {
      batch.insert(
        'track_cover_cache',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Set<String>> loadReferencedCoverArtPaths() async {
    final rows = await _db.rawQuery('''
      SELECT cover_art_path FROM tracks
        WHERE cover_art_path IS NOT NULL AND cover_art_path != ''
      UNION
      SELECT cover_art_path FROM folders
        WHERE cover_art_path IS NOT NULL AND cover_art_path != ''
      UNION
      SELECT cover_art_path FROM albums
        WHERE cover_art_path IS NOT NULL AND cover_art_path != ''
      UNION
      SELECT track_cover_cache.cover_art_path
      FROM track_cover_cache
      INNER JOIN tracks
        ON tracks.path = track_cover_cache.path
       AND tracks.size_bytes = track_cover_cache.size_bytes
       AND tracks.modified_ms = track_cover_cache.modified_ms
      WHERE track_cover_cache.cover_art_path IS NOT NULL
        AND track_cover_cache.cover_art_path != ''
    ''');
    return rows.map((row) => row['cover_art_path']).whereType<String>().toSet();
  }

  Future<void> replaceLibrary(ScanResult result) async {
    await _db.transaction((txn) async {
      await _clearLibraryTables(txn, clearTrackCoverCache: false);

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

  Future<void> saveMusicRootAndClearLibrary(String rootPath) async {
    await _db.transaction((txn) async {
      await txn.insert('settings', {
        'key': musicRootSettingKey,
        'value': normalizeMusicRootPath(rootPath),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _clearLibraryTables(
        txn,
        clearTrackCoverCache: true,
        clearLastPlayback: true,
      );
    });
  }

  Future<void> saveScanState(ScanResult result) async {
    await _db.transaction((txn) async {
      await txn.delete('scan_state');
      await txn.insert('scan_state', _scanStateMap(result));
    });
  }

  Future<Map<String, Object?>?> loadScanState() async {
    final rows = await _db.query('scan_state', limit: 1);
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<String> loadMusicRoot() async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [musicRootSettingKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return defaultMusicRoot;
    }
    final value = normalizeMusicRootPath(rows.first['value'] as String);
    return value.isEmpty ? defaultMusicRoot : value;
  }

  Future<void> saveMusicRoot(String rootPath) async {
    await _db.insert('settings', {
      'key': musicRootSettingKey,
      'value': normalizeMusicRootPath(rootPath),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> loadThemeMode() async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [themeModeSettingKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 'light';
    }
    final value = rows.first['value'] as String;
    return value == 'dark' ? 'dark' : 'light';
  }

  Future<void> saveThemeMode(String value) async {
    await _db.insert('settings', {
      'key': themeModeSettingKey,
      'value': value == 'dark' ? 'dark' : 'light',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<LastPlaybackState?> loadLastPlayback() async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [lastPlaybackSettingKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rows.first['value'] as String);
      if (decoded is! Map) {
        return null;
      }
      return LastPlaybackState.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastPlayback(LastPlaybackState state) async {
    await _db.insert('settings', {
      'key': lastPlaybackSettingKey,
      'value': jsonEncode(state.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<LlmSettings> loadLlmSettings() async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [llmSettingsSettingKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const LlmSettings.defaults();
    }
    try {
      final decoded = jsonDecode(rows.first['value'] as String);
      if (decoded is! Map) {
        return const LlmSettings.defaults();
      }
      return LlmSettings.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return const LlmSettings.defaults();
    }
  }

  Future<void> saveLlmSettings(LlmSettings settings) async {
    await _db.insert('settings', {
      'key': llmSettingsSettingKey,
      'value': jsonEncode(settings.normalized().toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AudioOutputSettings> loadAudioOutputSettings() async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [audioOutputSettingsSettingKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const AudioOutputSettings.defaults();
    }
    try {
      final decoded = jsonDecode(rows.first['value'] as String);
      if (decoded is! Map) {
        return const AudioOutputSettings.defaults();
      }
      return AudioOutputSettings.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return const AudioOutputSettings.defaults();
    }
  }

  Future<void> saveAudioOutputSettings(AudioOutputSettings settings) async {
    await _db.insert('settings', {
      'key': audioOutputSettingsSettingKey,
      'value': jsonEncode(settings.normalized().toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
        batch.delete(
          'track_cover_cache',
          where: 'path = ?',
          whereArgs: [change.path],
        );
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
    await _createTrackCoverCacheTable(db);
    await _createSettingsTable(db);
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

  static Future<void> _upgradeToV3(Database db) async {
    await _createTrackCoverCacheTable(db);
  }

  static Future<void> _upgradeToV4(Database db) async {
    await _createSettingsTable(db);
  }

  static Future<void> _createTrackCoverCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS track_cover_cache (
        path TEXT PRIMARY KEY,
        size_bytes INTEGER NOT NULL,
        modified_ms INTEGER NOT NULL,
        cover_art_path TEXT,
        checked_at_ms INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _clearLibraryTables(
    Transaction txn, {
    required bool clearTrackCoverCache,
    bool clearLastPlayback = false,
  }) async {
    await txn.delete('tracks');
    await txn.delete('folders');
    await txn.delete('albums');
    await txn.delete('scan_state');
    if (clearTrackCoverCache) {
      await txn.delete('track_cover_cache');
    }
    if (clearLastPlayback) {
      await txn.delete(
        'settings',
        where: 'key = ?',
        whereArgs: [lastPlaybackSettingKey],
      );
    }
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
