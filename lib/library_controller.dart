import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_diagnostics.dart';
import 'audio_output_settings.dart';
import 'cover_cache.dart';
import 'library_database.dart';
import 'library_diff.dart';
import 'library_formatters.dart';
import 'library_scan_state.dart';
import 'library_scan_task.dart';
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
  }) : _scanTask = LibraryScanTask(scanner ?? MusicScanner()),
       _coverIndexer = coverIndexer ?? TrackCoverIndexer(),
       _openDatabase = openDatabase ?? LibraryDatabase.open,
       _migrateCoverCache = migrateCoverCache ?? _migrateCoverCacheSafely,
       _persistThemeMode = persistThemeMode ?? _persistThemeModeToDatabase {
    _scanTask.addListener(_handleScanChanged);
  }

  final LibraryScanTask _scanTask;
  final TrackCoverIndexer _coverIndexer;
  final LibraryDatabaseOpener _openDatabase;
  final CoverCacheMigrator _migrateCoverCache;
  final ThemeModePersister _persistThemeMode;
  ValueListenable<RescanUiState> get rescanState => _scanTask;
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
  String? _backgroundWarning;
  bool _loading = true;
  bool _settingsLoaded = false;
  bool _disposed = false;
  String? _error;

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
  ScanProgress? get scanProgress =>
      _scanTask.running ? _scanTask.value.progress : null;
  String? get backgroundWarning => _backgroundWarning;
  bool get loading => _loading;
  bool get settingsLoaded => _settingsLoaded;
  bool get scanning => _scanTask.running;
  String? get error => _error;
  bool get canChangeMusicRoot => _database != null && !scanning;
  bool get canRestoreLastPlayback =>
      !_loading && !scanning && !_scanRootChanged;

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
    if (database == null || scanning || _disposed) return;
    await _replaceLibraryWithScan(database, rootPath: _musicRoot);
  }

  Future<void> startRescanDiff({bool full = false}) async {
    if (scanning || rescanState.value.phase.isBusy || _disposed) return;
    await _runRescanDiff(full: full);
  }

  void cancelScan() {
    if (!_disposed) _scanTask.cancel();
  }

  void prepareRescanDialog() {
    final state = rescanState.value;
    if (state.phase == RescanPhase.done &&
        state.diff == null &&
        _tracks.isNotEmpty) {
      _scanTask.value = const RescanUiState(phase: RescanPhase.idle);
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

    _scanTask.value = rescanState.value.copyWith(
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
      _scanTask.value = const RescanUiState(
        phase: RescanPhase.done,
        message: 'Library refreshed',
      );
      _emit();
      return diff;
    } catch (error) {
      if (!_disposed) {
        _scanTask.value = rescanState.value.copyWith(
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
    if (database == null || scanning || _disposed) return false;
    final normalizedRoot = normalizeMusicRootPath(nextRoot);
    if (!await Directory(normalizedRoot).exists()) {
      _setError('Music folder does not exist: $normalizedRoot');
      return false;
    }
    if (_disposed || scanning) return false;
    return _replaceLibraryWithScan(
      database,
      rootPath: normalizedRoot,
      changingRoot: true,
    );
  }

  Future<bool> _replaceLibraryWithScan(
    LibraryDatabase database, {
    required String rootPath,
    bool changingRoot = false,
  }) async {
    return await _runScan<bool>(
          initialState: RescanUiState(
            mode: LibraryScanMode.direct,
            phase: RescanPhase.scanning,
            message: changingRoot
                ? 'Scanning new music folder'
                : 'Scanning music folder',
            progress: ScanProgress(
              filesSeen: 0,
              tracksParsed: 0,
              currentPath: rootPath,
            ),
          ),
          errorMessage: 'Music folder scan failed',
          work: () async {
            final result = await _scanTask.scan(rootPath);
            if (_disposed) return false;
            if (changingRoot) {
              await database.replaceLibraryForMusicRoot(rootPath, result);
            } else {
              await database.replaceLibrary(result);
            }
            if (_disposed) return false;
            _musicRoot = rootPath;
            await _loadFromDatabase();
            if (_disposed) return false;
            _scanTask.value = RescanUiState(
              mode: LibraryScanMode.direct,
              phase: RescanPhase.done,
              message: 'Library refreshed',
            );
            return true;
          },
        ) ??
        false;
  }

  Future<T?> _runScan<T>({
    required RescanUiState initialState,
    required String errorMessage,
    required Future<T> Function() work,
    List<Track>? Function()? previewTracks,
  }) async {
    _coverIndexer.cancel();
    _loading = false;
    _error = null;
    try {
      return await _scanTask.run(
        initialState: initialState,
        errorMessage: errorMessage,
        work: work,
      );
    } finally {
      if (!_disposed) {
        final preview = previewTracks?.call();
        _startBackgroundCoverIndexing(
          preview ?? _tracks,
          knownCache: preview == null ? _trackCoverCache : null,
          pruneWhenComplete: preview == null,
        );
      }
    }
  }

  void _handleScanChanged() {
    _error = _scanTask.value.error;
    _emit();
  }

  Future<void> saveLastPlayback(LastPlaybackState state) async {
    final database = _database;
    if (database == null || _disposed) {
      return;
    }
    await database.saveLastPlayback(state);
    if (!_disposed) {
      _lastPlayback = state;
    }
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
    if (!scanning) {
      _startBackgroundCoverIndexing(tracks, knownCache: trackCoverCache);
    }
  }

  Future<void> _runRescanDiff({required bool full}) async {
    final database = _database;
    if (database == null || _disposed) return;
    List<Track>? previewTracks;
    await _runScan<void>(
      initialState: const RescanUiState(
        phase: RescanPhase.loadingDatabase,
        message: 'Loading current library snapshot',
      ),
      errorMessage: 'Rescan failed',
      previewTracks: () => previewTracks,
      work: () async {
        final snapshot = await database.loadSnapshot();
        if (_disposed) return;
        _scanTask.value = RescanUiState(
          phase: RescanPhase.scanning,
          message: full ? 'Fully scanning local files' : 'Scanning local files',
        );
        final result = await _scanTask.scan(
          _musicRoot,
          previousTracks: full ? null : snapshot.tracks,
        );
        previewTracks = result.tracks;
        if (_disposed) return;
        _scanTask.value = _scanTask.value.copyWith(
          phase: RescanPhase.diffing,
          message: 'Comparing scan with database',
          progress: null,
        );
        final diff = diffLibrary(snapshot, result);
        if (!diff.hasChanges) {
          await database.applyDiff(diff);
          if (_disposed) return;
          _folders = await database.loadFolders();
          _albums = await database.loadAlbums();
          _refreshFolderDerivedState();
          _scanState = await database.loadScanState();
          if (_disposed) return;
          _emit();
        }
        _scanTask.value = RescanUiState(
          phase: RescanPhase.ready,
          message: diff.hasChanges
              ? 'Review changes before applying'
              : 'Library is up to date',
          diff: diff,
        );
      },
    );
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
        shouldPause: () => scanning || _disposed,
        onCacheUpdated: (updates) {
          if (_disposed || updates.isEmpty) {
            return;
          }
          _setTrackCoverCache({..._trackCoverCache, ...updates});
          _emit();
        },
      );
      if (completed && pruneWhenComplete && !_disposed && !scanning) {
        await _pruneUnusedCoverCache(database);
      }
    } catch (error, stackTrace) {
      _setBackgroundWarning('Cover art update failed');
      reportAppError('background cover indexing', error, stackTrace);
    }
  }

  Future<void> _pruneUnusedCoverCache(LibraryDatabase database) async {
    try {
      final referencedPaths = await database.loadReferencedCoverArtPaths();
      await pruneCoverCacheFiles(referencedPaths);
    } catch (error, stackTrace) {
      _setBackgroundWarning('Cover cache cleanup failed');
      reportAppError('cover cache pruning', error, stackTrace);
    }
  }

  void clearBackgroundWarning() {
    if (_backgroundWarning == null || _disposed) {
      return;
    }
    _backgroundWarning = null;
    _emit();
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
    } catch (error, stackTrace) {
      reportAppError('cover cache migration', error, stackTrace);
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
    _scanTask.dispose();
    _coverIndexer.dispose();
    trackCoverCacheListenable.dispose();
    unawaited(_database?.close());
    super.dispose();
  }
}
