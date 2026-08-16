import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'audio_output_settings.dart';
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
typedef CoverCacheMigrator = Future<void> Function(LibraryDatabase database);
typedef ThemeModePersister =
    Future<void> Function(LibraryDatabase database, String value);

class LibraryController extends ChangeNotifier {
  LibraryController({
    MusicScanner? scanner,
    TrackCoverIndexer? coverIndexer,
    LibraryDatabaseOpener? openDatabase,
    CoverCacheMigrator? migrateCoverCache,
    ThemeModePersister? persistThemeMode,
  }) : _scanner = scanner ?? MusicScanner(),
       _coverIndexer = coverIndexer ?? TrackCoverIndexer(),
       _openDatabase = openDatabase ?? LibraryDatabase.open,
       _migrateCoverCache = migrateCoverCache ?? _migrateCoverCacheSafely,
       _persistThemeMode = persistThemeMode ?? _persistThemeModeToDatabase;

  final MusicScanner _scanner;
  final TrackCoverIndexer _coverIndexer;
  final LibraryDatabaseOpener _openDatabase;
  final CoverCacheMigrator _migrateCoverCache;
  final ThemeModePersister _persistThemeMode;
  final ValueNotifier<RescanUiState> rescanState = ValueNotifier(
    const RescanUiState(phase: RescanPhase.idle),
  );
  final ValueNotifier<Map<String, String?>> trackCoverCacheListenable =
      ValueNotifier(const {});

  LibraryDatabase? _database;
  List<Track> _tracks = const [];
  List<FolderSummary> _folders = const [];
  List<AlbumSummary> _albums = const [];
  List<Track> _favoriteTracks = const [];
  Set<String> _favoriteTrackPaths = const {};
  List<FolderSummary> _playlistFolders = const [];
  Map<String, List<Track>> _tracksByFolder = const {};
  Map<String, String?> _trackCoverCache = const {};
  Map<String, Object?>? _scanState;
  LastPlaybackState? _lastPlayback;
  AudioOutputSettings _audioOutputSettings =
      const AudioOutputSettings.defaults();
  String _musicRoot = defaultMusicRoot;
  String _themeMode = 'light';
  ScanProgress? _scanProgress;
  String? _backgroundWarning;
  bool _loading = true;
  bool _settingsLoaded = false;
  bool _scanning = false;
  bool _disposed = false;
  String? _error;
  Future<void>? _rescanTask;

  List<Track> get tracks => _tracks;
  List<FolderSummary> get folders => _folders;
  List<AlbumSummary> get albums => _albums;
  List<Track> get favoriteTracks => _favoriteTracks;
  Set<String> get favoriteTrackPaths => _favoriteTrackPaths;
  Map<String, String?> get trackCoverCache => _trackCoverCache;
  Map<String, Object?>? get scanState => _scanState;
  LastPlaybackState? get lastPlayback => _lastPlayback;
  AudioOutputSettings get audioOutputSettings => _audioOutputSettings;
  String get musicRoot => _musicRoot;
  String get themeMode => _themeMode;
  ScanProgress? get scanProgress => _scanProgress;
  String? get backgroundWarning => _backgroundWarning;
  bool get loading => _loading;
  bool get settingsLoaded => _settingsLoaded;
  bool get scanning => _scanning;
  String? get error => _error;
  bool get canChangeMusicRoot => _database != null && !_scanning;
  bool get canRestoreLastPlayback =>
      !_loading && !_scanning && !_scanRootChanged;

  List<FolderSummary> get playlistFolders => _playlistFolders;

  int get playlistCount => _playlistFolders.length;

  int get favoriteCount => _favoriteTracks.length;

  Map<String, List<Track>> get tracksByFolder => _tracksByFolder;

  Future<void> open() async {
    try {
      final database = await _openDatabase();
      if (_disposed) {
        await database.close();
        return;
      }
      _database = database;
      final musicRoot = await database.loadMusicRoot();
      final themeMode = await database.loadThemeMode();
      final audioOutputSettings = await database.loadAudioOutputSettings();
      if (_disposed) {
        return;
      }
      _musicRoot = musicRoot;
      _themeMode = themeMode;
      _audioOutputSettings = audioOutputSettings;
      _settingsLoaded = true;
      _emit();
      await _migrateCoverCache(database);
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
    await _replaceLibraryWithScan(
      database,
      message: 'Scanning music folder',
      errorMessage: 'Music folder scan failed',
    );
  }

  void startRescanDiff({bool full = false}) {
    if (_rescanTask != null || rescanState.value.phase.isBusy || _disposed) {
      return;
    }
    _scanner.prepareForScan();
    _rescanTask = _runRescanDiff(full: full).whenComplete(() {
      _rescanTask = null;
    });
  }

  void cancelScan() {
    if (_disposed) {
      return;
    }
    _scanner.cancel();
  }

  void prepareRescanDialog() {
    final state = rescanState.value;
    if (state.phase == RescanPhase.done &&
        state.diff == null &&
        _tracks.isNotEmpty) {
      rescanState.value = const RescanUiState(phase: RescanPhase.idle);
    }
  }

  Future<LibraryDiff?> applyPendingDiff({
    required LargeDeletionConfirmation confirmLargeDeletion,
  }) async {
    final database = _database;
    final state = rescanState.value;
    final diff = state.diff;
    if (database == null ||
        state.mode != LibraryScanMode.diff ||
        diff == null ||
        !diff.hasChanges ||
        _disposed) {
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
      rescanState.value = const RescanUiState(
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

    final normalizedRoot = normalizeMusicRootPath(nextRoot);
    if (!await Directory(normalizedRoot).exists()) {
      _setError('Music folder does not exist: $normalizedRoot');
      return false;
    }

    _scanner.prepareForScan();
    _coverIndexer.cancel();
    _scanning = true;
    _loading = false;
    _error = null;
    _scanProgress = ScanProgress(
      filesSeen: 0,
      tracksParsed: 0,
      currentPath: normalizedRoot,
    );
    rescanState.value = RescanUiState(
      mode: LibraryScanMode.direct,
      phase: RescanPhase.scanning,
      message: 'Scanning new music folder',
      progress: _scanProgress,
    );
    _emit();

    var switched = false;
    try {
      final result = await _scanner.scan(
        normalizedRoot,
        onProgress: (progress) {
          if (_disposed) {
            return;
          }
          _scanProgress = progress;
          rescanState.value = RescanUiState(
            mode: LibraryScanMode.direct,
            phase: RescanPhase.scanning,
            message: 'Scanning new music folder',
            progress: progress,
          );
          _emit();
        },
      );
      if (_disposed) {
        return false;
      }
      await database.replaceLibraryForMusicRoot(normalizedRoot, result);
      if (_disposed) {
        return false;
      }
      _musicRoot = normalizedRoot;
      await _loadFromDatabase();
      if (_disposed) {
        return false;
      }
      switched = true;
      rescanState.value = RescanUiState(
        mode: LibraryScanMode.direct,
        phase: RescanPhase.done,
        message: _libraryRefreshMessage(result),
        errorSamples: result.errorSamples,
      );
      _emit();
      return true;
    } on ScanCancelledException {
      if (!_disposed) {
        _markScanCancelled(mode: LibraryScanMode.direct);
      }
      return false;
    } catch (error) {
      if (!_disposed) {
        final message = error.toString();
        _error = message;
        rescanState.value = RescanUiState(
          mode: LibraryScanMode.direct,
          phase: RescanPhase.error,
          message: 'Music folder scan failed',
          error: message,
        );
        _emit();
      }
      return false;
    } finally {
      if (!_disposed) {
        _scanning = false;
        _scanProgress = null;
        _emit();
        if (!switched) {
          _startBackgroundCoverIndexing(_tracks, knownCache: _trackCoverCache);
        }
      }
    }
  }

  Future<bool> _replaceLibraryWithScan(
    LibraryDatabase database, {
    required String message,
    required String errorMessage,
  }) async {
    _scanner.prepareForScan();
    _coverIndexer.cancel();
    _scanning = true;
    _loading = false;
    _error = null;
    _scanProgress = ScanProgress(
      filesSeen: 0,
      tracksParsed: 0,
      currentPath: _musicRoot,
    );
    rescanState.value = RescanUiState(
      mode: LibraryScanMode.direct,
      phase: RescanPhase.scanning,
      message: message,
      progress: _scanProgress,
    );
    _emit();

    var replaced = false;
    try {
      final result = await _scanner.scan(
        _musicRoot,
        onProgress: (progress) {
          if (_disposed) {
            return;
          }
          _scanProgress = progress;
          rescanState.value = RescanUiState(
            mode: LibraryScanMode.direct,
            phase: RescanPhase.scanning,
            message: message,
            progress: progress,
          );
          _emit();
        },
      );
      if (_disposed) {
        return false;
      }
      await database.replaceLibrary(result);
      if (_disposed) {
        return false;
      }
      await _loadFromDatabase();
      if (_disposed) {
        return false;
      }
      rescanState.value = RescanUiState(
        mode: LibraryScanMode.direct,
        phase: RescanPhase.done,
        message: _libraryRefreshMessage(result),
        errorSamples: result.errorSamples,
      );
      _emit();
      replaced = true;
      return true;
    } on ScanCancelledException {
      if (!_disposed) {
        _markScanCancelled(mode: LibraryScanMode.direct);
      }
      return false;
    } catch (error) {
      if (!_disposed) {
        final message = error.toString();
        _error = message;
        rescanState.value = RescanUiState(
          mode: LibraryScanMode.direct,
          phase: RescanPhase.error,
          message: errorMessage,
          error: message,
        );
        _emit();
      }
      return false;
    } finally {
      if (!_disposed) {
        _scanning = false;
        _scanProgress = null;
        _emit();
        if (!replaced) {
          _startBackgroundCoverIndexing(_tracks, knownCache: _trackCoverCache);
        }
      }
    }
  }

  Future<void> saveLastPlayback(LastPlaybackState state) async {
    final database = _database;
    if (database == null || _disposed) {
      return;
    }
    _lastPlayback = state;
    await database.saveLastPlayback(state);
  }

  Future<void> toggleFavoriteTrack(Track track) async {
    final database = _database;
    if (database == null || _disposed) {
      return;
    }
    final nextFavorite = !_favoriteTrackPaths.contains(track.path);
    await database.setTrackFavorite(track.path, nextFavorite);
    if (_disposed) {
      return;
    }
    if (nextFavorite) {
      _favoriteTrackPaths = {..._favoriteTrackPaths, track.path};
      _favoriteTracks = [
        track,
        for (final favorite in _favoriteTracks)
          if (favorite.path != track.path) favorite,
      ];
    } else {
      _favoriteTrackPaths = _favoriteTrackPaths
          .where((path) => path != track.path)
          .toSet();
      _favoriteTracks = _favoriteTracks
          .where((favorite) => favorite.path != track.path)
          .toList(growable: false);
    }
    _emit();
  }

  Future<void> saveAudioOutputSettings(AudioOutputSettings settings) async {
    final database = _database;
    if (database == null || _disposed) {
      return;
    }
    _audioOutputSettings = settings.normalized();
    await database.saveAudioOutputSettings(_audioOutputSettings);
    _emit();
  }

  Future<void> saveThemeMode(String value) async {
    final database = _database;
    if (database == null || _disposed) {
      return;
    }
    final nextMode = value == 'dark' ? 'dark' : 'light';
    await _persistThemeMode(database, nextMode);
    if (_disposed) {
      return;
    }
    _themeMode = nextMode;
    _emit();
  }

  Future<void> _loadFromDatabase() async {
    final database = _database;
    if (database == null || _disposed) {
      return;
    }

    final tracks = await database.loadTracks();
    final folders = await database.loadFolders();
    final albums = await database.loadAlbums();
    final favoriteTracks = await database.loadFavoriteTracks();
    final scanState = await database.loadScanState();
    final lastPlayback = await database.loadLastPlayback();
    final trackCoverCache = await database.loadTrackCoverCache(tracks);

    if (_disposed) {
      return;
    }
    _tracks = tracks;
    _folders = folders;
    _albums = albums;
    _favoriteTracks = favoriteTracks;
    _favoriteTrackPaths = favoriteTracks.map((track) => track.path).toSet();
    _refreshDerivedLibraryState();
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
        _refreshFolderDerivedState();
        _scanState = await database.loadScanState();
        if (_disposed) {
          return;
        }
        _emit();
      }
      rescanState.value = RescanUiState(
        phase: RescanPhase.ready,
        message: _rescanReadyMessage(diff),
        diff: diff,
        errorSamples: result.errorSamples,
      );
      _emit();
    } on ScanCancelledException {
      if (!_disposed) {
        _markScanCancelled();
      }
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
      _setBackgroundWarning('Cover art update failed');
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
      _setBackgroundWarning('Cover cache cleanup failed');
      _debugLogBackgroundTaskFailure('cover cache pruning', error, stackTrace);
    }
  }

  void clearBackgroundWarning() {
    if (_backgroundWarning == null || _disposed) {
      return;
    }
    _backgroundWarning = null;
    _emit();
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

  void _refreshDerivedLibraryState() {
    _refreshTrackDerivedState();
    _refreshFolderDerivedState();
  }

  void _refreshTrackDerivedState() {
    _tracksByFolder = tracksByFolderMap(_tracks);
  }

  void _refreshFolderDerivedState() {
    _playlistFolders = _folders
        .where((folder) => folder.kind == FolderKind.playlist)
        .toList(growable: false);
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

  void _markScanCancelled({LibraryScanMode mode = LibraryScanMode.diff}) {
    _error = null;
    rescanState.value = RescanUiState(
      mode: mode,
      phase: RescanPhase.idle,
      message: 'Scan cancelled',
    );
    _emit();
  }

  void _setBackgroundWarning(String message) {
    if (_disposed) {
      return;
    }
    _backgroundWarning = message;
    _emit();
  }

  static Future<void> _persistThemeModeToDatabase(
    LibraryDatabase database,
    String value,
  ) {
    return database.saveThemeMode(value);
  }

  static Future<void> _migrateCoverCacheSafely(LibraryDatabase database) async {
    try {
      final migration = await migrateLegacyCoverCache();
      if (migration.shouldRewritePaths && migration.legacyDir != null) {
        await database.relocateCoverArtPaths(
          fromDir: migration.legacyDir!,
          toDir: migration.currentDir,
        );
      }
    } catch (_) {}
  }

  static String _libraryRefreshMessage(ScanResult result) {
    return _skippedFilesMessage('Library refreshed', result);
  }

  static String _rescanReadyMessage(LibraryDiff diff) {
    final base = diff.hasChanges
        ? 'Review changes before applying'
        : 'Library is up to date';
    return _skippedFilesMessage(base, diff.result);
  }

  static String _skippedFilesMessage(String base, ScanResult result) {
    if (result.skippedFiles <= 0) {
      return base;
    }
    return '$base. Skipped ${result.skippedFiles} unreadable files';
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
    _scanner.cancel();
    _coverIndexer.dispose();
    rescanState.dispose();
    trackCoverCacheListenable.dispose();
    unawaited(_database?.close());
    super.dispose();
  }
}
