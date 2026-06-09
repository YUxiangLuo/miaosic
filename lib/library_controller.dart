import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'cover_cache.dart';
import 'library_database.dart';
import 'library_diff.dart';
import 'library_formatters.dart';
import 'library_types.dart';
import 'models.dart';
import 'music_scanner.dart';
import 'playlist_cover_indexer.dart';

typedef LibraryDatabaseOpener = Future<LibraryDatabase> Function();
typedef LargeDeletionConfirmation = Future<bool> Function(DeletionRisk risk);

class LibraryController extends ChangeNotifier {
  LibraryController({
    MusicScanner? scanner,
    TrackCoverIndexer? coverIndexer,
    LibraryDatabaseOpener? openDatabase,
  }) : _scanner = scanner ?? MusicScanner(),
       _coverIndexer = coverIndexer ?? TrackCoverIndexer(),
       _openDatabase = openDatabase ?? LibraryDatabase.open;

  final MusicScanner _scanner;
  final TrackCoverIndexer _coverIndexer;
  final LibraryDatabaseOpener _openDatabase;
  final ValueNotifier<RescanUiState> rescanState = ValueNotifier(
    const RescanUiState(phase: RescanPhase.idle),
  );
  final ValueNotifier<Map<String, String?>> trackCoverCacheListenable =
      ValueNotifier(const {});

  LibraryDatabase? _database;
  List<Track> _tracks = const [];
  List<FolderSummary> _folders = const [];
  List<AlbumSummary> _albums = const [];
  Map<String, String?> _trackCoverCache = const {};
  Map<String, Object?>? _scanState;
  LastPlaybackState? _lastPlayback;
  String _musicRoot = defaultMusicRoot;
  ScanProgress? _scanProgress;
  bool _loading = true;
  bool _scanning = false;
  bool _disposed = false;
  String? _error;
  Future<void>? _rescanTask;

  List<Track> get tracks => _tracks;
  List<FolderSummary> get folders => _folders;
  List<AlbumSummary> get albums => _albums;
  Map<String, String?> get trackCoverCache => _trackCoverCache;
  Map<String, Object?>? get scanState => _scanState;
  LastPlaybackState? get lastPlayback => _lastPlayback;
  String get musicRoot => _musicRoot;
  ScanProgress? get scanProgress => _scanProgress;
  bool get loading => _loading;
  bool get scanning => _scanning;
  String? get error => _error;
  bool get canChangeMusicRoot => _database != null && !_scanning;
  bool get canRestoreLastPlayback =>
      !_loading && !_scanning && !_scanRootChanged;

  List<FolderSummary> get playlistFolders =>
      _folders.where((folder) => folder.kind == FolderKind.playlist).toList();

  int get playlistCount =>
      _folders.where((folder) => folder.kind == FolderKind.playlist).length;

  Map<String, List<Track>> get tracksByFolder => tracksByFolderMap(_tracks);

  Future<void> open() async {
    try {
      final database = await _openDatabase();
      if (_disposed) {
        await database.close();
        return;
      }
      _database = database;
      _musicRoot = await database.loadMusicRoot();
      if (_disposed) {
        return;
      }
      await _loadFromDatabase();
      if (_disposed) {
        return;
      }
      if (_tracks.isEmpty || _needsCoverCacheRefresh || _scanRootChanged) {
        await scanLibrary();
      }
    } catch (error) {
      _setError(error.toString(), loading: false);
    }
  }

  Future<void> scanLibrary() async {
    final database = _database;
    if (database == null || _scanning || _disposed) {
      return;
    }

    _coverIndexer.cancel();
    _scanning = true;
    _loading = false;
    _error = null;
    _scanProgress = ScanProgress(
      filesSeen: 0,
      tracksParsed: 0,
      currentPath: _musicRoot,
    );
    _emit();

    try {
      final result = await _scanner.scan(
        _musicRoot,
        onProgress: (progress) {
          if (_disposed) {
            return;
          }
          _scanProgress = progress;
          _emit();
        },
      );
      if (_disposed) {
        return;
      }
      await database.replaceLibrary(result);
      if (_disposed) {
        return;
      }
      await _loadFromDatabase();
    } catch (error) {
      _setError(error.toString());
    } finally {
      if (!_disposed) {
        _scanning = false;
        _scanProgress = null;
        _emit();
      }
    }
  }

  void startRescanDiff({bool full = false}) {
    if (_rescanTask != null || rescanState.value.phase.isBusy || _disposed) {
      return;
    }
    _rescanTask = _runRescanDiff(full: full).whenComplete(() {
      _rescanTask = null;
    });
  }

  Future<LibraryDiff?> applyPendingDiff({
    required LargeDeletionConfirmation confirmLargeDeletion,
  }) async {
    final database = _database;
    final diff = rescanState.value.diff;
    if (database == null || diff == null || !diff.hasChanges || _disposed) {
      return null;
    }

    final risk = diff.deletionRisk();
    if (risk.isLargeDeletion) {
      final confirmed = await confirmLargeDeletion(risk);
      if (_disposed || !confirmed) {
        return null;
      }
    }

    rescanState.value = rescanState.value.copyWith(
      phase: RescanPhase.applying,
      message: 'Applying library changes',
    );
    _emit();

    try {
      await database.applyDiff(diff);
      if (_disposed) {
        return null;
      }
      await _loadFromDatabase();
      if (_disposed) {
        return null;
      }
      rescanState.value = rescanState.value.copyWith(
        phase: RescanPhase.done,
        message: 'Library refreshed',
      );
      _emit();
      return diff;
    } catch (error) {
      if (!_disposed) {
        rescanState.value = rescanState.value.copyWith(
          phase: RescanPhase.error,
          message: 'Apply failed',
          error: error.toString(),
        );
        _emit();
      }
      return null;
    }
  }

  Future<bool> changeMusicRoot(String nextRoot) async {
    final database = _database;
    if (database == null || _scanning || _disposed) {
      return false;
    }

    if (!await Directory(nextRoot).exists()) {
      _setError('Music folder does not exist: $nextRoot');
      return false;
    }

    await database.saveMusicRoot(nextRoot);
    if (_disposed) {
      return false;
    }
    _coverIndexer.cancel();
    _musicRoot = nextRoot;
    _error = null;
    _emit();
    await scanLibrary();
    return true;
  }

  Future<void> saveLastPlayback(LastPlaybackState state) async {
    final database = _database;
    if (database == null || _disposed) {
      return;
    }
    _lastPlayback = state;
    await database.saveLastPlayback(state);
  }

  Future<void> _loadFromDatabase() async {
    final database = _database;
    if (database == null || _disposed) {
      return;
    }

    final tracks = await database.loadTracks();
    final folders = await database.loadFolders();
    final albums = await database.loadAlbums();
    final scanState = await database.loadScanState();
    final lastPlayback = await database.loadLastPlayback();
    final trackCoverCache = await database.loadTrackCoverCache(tracks);

    if (_disposed) {
      return;
    }
    _tracks = tracks;
    _folders = folders;
    _albums = albums;
    _setTrackCoverCache(trackCoverCache, tracks: tracks);
    _scanState = scanState;
    _lastPlayback = lastPlayback;
    _loading = false;
    _emit();
    _startBackgroundCoverIndexing(tracks, knownCache: trackCoverCache);
  }

  Future<void> _runRescanDiff({required bool full}) async {
    final database = _database;
    if (database == null || _disposed) {
      return;
    }

    List<Track>? rescanResultTracks;
    _coverIndexer.cancel();
    _scanning = true;
    _error = null;
    _scanProgress = null;
    rescanState.value = const RescanUiState(
      phase: RescanPhase.loadingDatabase,
      message: 'Loading current library snapshot',
    );
    _emit();

    try {
      final snapshot = await database.loadSnapshot();
      if (_disposed) {
        return;
      }
      rescanState.value = RescanUiState(
        phase: RescanPhase.scanning,
        message: full ? 'Fully scanning local files' : 'Scanning local files',
      );
      _emit();

      final result = await _scanner.scan(
        _musicRoot,
        previousTracks: full ? null : snapshot.tracks,
        onProgress: (progress) {
          if (_disposed) {
            return;
          }
          _scanProgress = progress;
          rescanState.value = rescanState.value.copyWith(
            progress: progress,
            message: full
                ? 'Fully scanning local files'
                : 'Scanning local files',
          );
          _emit();
        },
      );
      rescanResultTracks = result.tracks;
      if (_disposed) {
        return;
      }

      rescanState.value = rescanState.value.copyWith(
        phase: RescanPhase.diffing,
        message: 'Comparing scan with database',
        progress: null,
      );
      _emit();

      final diff = diffLibrary(snapshot, result);
      if (!diff.hasChanges) {
        await database.applyDiff(diff);
        if (_disposed) {
          return;
        }
        _folders = await database.loadFolders();
        _albums = await database.loadAlbums();
        _scanState = await database.loadScanState();
        if (_disposed) {
          return;
        }
        _emit();
      }
      rescanState.value = RescanUiState(
        phase: RescanPhase.ready,
        message: diff.hasChanges
            ? 'Review changes before applying'
            : 'Library is up to date',
        diff: diff,
      );
      _emit();
    } catch (error) {
      if (!_disposed) {
        rescanState.value = RescanUiState(
          phase: RescanPhase.error,
          message: 'Rescan failed',
          error: error.toString(),
        );
        _error = error.toString();
        _emit();
      }
    } finally {
      if (!_disposed) {
        _scanning = false;
        _scanProgress = null;
        _emit();
        final tracksForIndexing = rescanResultTracks;
        if (tracksForIndexing == null) {
          _startBackgroundCoverIndexing(_tracks, knownCache: _trackCoverCache);
        } else {
          _startBackgroundCoverIndexing(
            tracksForIndexing,
            pruneWhenComplete: false,
          );
        }
      }
    }
  }

  bool get _needsCoverCacheRefresh {
    final version = _scanState?['cover_cache_version'] as int?;
    return _tracks.isNotEmpty && (version ?? 0) < 1;
  }

  bool get _scanRootChanged {
    final scannedRoot = _scanState?['root_path'] as String?;
    return _tracks.isNotEmpty &&
        scannedRoot != null &&
        scannedRoot != _musicRoot;
  }

  void _startBackgroundCoverIndexing(
    List<Track> tracks, {
    Map<String, String?>? knownCache,
    bool pruneWhenComplete = true,
  }) {
    final database = _database;
    if (database == null || tracks.isEmpty || _disposed) {
      return;
    }
    unawaited(
      _runBackgroundCoverIndexing(
        database,
        tracks,
        knownCache,
        pruneWhenComplete,
      ),
    );
  }

  Future<void> _runBackgroundCoverIndexing(
    LibraryDatabase database,
    List<Track> tracks,
    Map<String, String?>? knownCache,
    bool pruneWhenComplete,
  ) async {
    try {
      final completed = await _coverIndexer.indexTracks(
        tracks: tracks,
        database: database,
        knownCache: knownCache,
        shouldPause: () => _scanning || _disposed,
        onCacheUpdated: (updates) {
          if (_disposed || updates.isEmpty) {
            return;
          }
          _setTrackCoverCache({..._trackCoverCache, ...updates});
          _emit();
        },
      );
      if (completed && pruneWhenComplete && !_disposed && !_scanning) {
        await _pruneUnusedCoverCache(database);
      }
    } catch (error, stackTrace) {
      _debugLogBackgroundTaskFailure(
        'background cover indexing',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _pruneUnusedCoverCache(LibraryDatabase database) async {
    try {
      final referencedPaths = await database.loadReferencedCoverArtPaths();
      await pruneCoverCacheFiles(referencedPaths);
    } catch (error, stackTrace) {
      _debugLogBackgroundTaskFailure('cover cache pruning', error, stackTrace);
    }
  }

  void _debugLogBackgroundTaskFailure(
    String task,
    Object error,
    StackTrace stackTrace,
  ) {
    assert(() {
      debugPrint('Miaosic $task failed: $error');
      debugPrintStack(stackTrace: stackTrace, label: 'Miaosic $task');
      return true;
    }());
  }

  void _setTrackCoverCache(Map<String, String?> cache, {List<Track>? tracks}) {
    final trackList = tracks;
    final nextCache = trackList == null
        ? cache
        : {
            for (final track in trackList)
              if (cache.containsKey(track.path)) track.path: cache[track.path],
          };
    _trackCoverCache = nextCache;
    if (!_disposed) {
      trackCoverCacheListenable.value = nextCache;
    }
  }

  void _setError(String error, {bool? loading}) {
    if (_disposed) {
      return;
    }
    _error = error;
    if (loading != null) {
      _loading = loading;
    }
    _emit();
  }

  void _emit() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _coverIndexer.dispose();
    rescanState.dispose();
    trackCoverCacheListenable.dispose();
    unawaited(_database?.close());
    super.dispose();
  }
}
