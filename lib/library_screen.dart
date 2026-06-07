import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'album_playback_view.dart';
import 'album_views.dart';
import 'cover_cache.dart';
import 'library_database.dart';
import 'library_diff.dart';
import 'library_formatters.dart';
import 'library_sidebar.dart';
import 'library_types.dart';
import 'models.dart';
import 'music_scanner.dart';
import 'playback_controller.dart';
import 'playlist_cover_indexer.dart';
import 'playlist_views.dart';
import 'rescan_dialog.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _scanner = MusicScanner();
  final _playback = PlaybackController();
  final _coverIndexer = TrackCoverIndexer();
  final _playlistListScrollController = ScrollController();
  final _rescanState = ValueNotifier<RescanUiState>(
    const RescanUiState(phase: RescanPhase.idle),
  );
  final _trackCoverCacheListenable = ValueNotifier<Map<String, String?>>(
    const {},
  );

  LibraryDatabase? _database;
  List<Track> _tracks = const [];
  List<FolderSummary> _folders = const [];
  List<AlbumSummary> _albums = const [];
  Map<String, String?> _trackCoverCache = const {};
  Map<String, Object?>? _scanState;
  _ActiveAlbumPlayback? _activeAlbumPlayback;
  _ActivePlaylistPlayback? _activePlaylistPlayback;
  String? _lastPlaybackPath;
  bool _lastPlaybackPlaying = false;
  String _musicRoot = defaultMusicRoot;
  ScanProgress? _scanProgress;
  LibraryView _view = LibraryView.albums;
  String? _selectedPlaylistPath;
  double _playlistListScrollOffset = 0;
  bool _loading = true;
  bool _scanning = false;
  String? _error;
  bool _rescanDialogOpen = false;
  Future<void>? _rescanTask;

  @override
  void initState() {
    super.initState();
    _playback.addListener(_handlePlaybackChanged);
    unawaited(_openLibrary());
  }

  @override
  void dispose() {
    _playlistListScrollController.dispose();
    _rescanState.dispose();
    _trackCoverCacheListenable.dispose();
    _coverIndexer.dispose();
    _playback
      ..removeListener(_handlePlaybackChanged)
      ..dispose();
    unawaited(_database?.close());
    super.dispose();
  }

  void _handlePlaybackChanged() {
    final activeAlbumPlayback = _activeAlbumPlayback;
    final activePlaylistPlayback = _activePlaylistPlayback;
    if (!mounted ||
        activeAlbumPlayback == null && activePlaylistPlayback == null) {
      return;
    }
    final displayTrack = activeAlbumPlayback == null
        ? activePlaylistPlayback == null
              ? null
              : _currentTrackForPlaylist(activePlaylistPlayback)
        : _currentTrackForAlbum(activeAlbumPlayback);
    final nextPath = displayTrack?.path;
    final nextPlaying = nextPath != null && _playback.playing;
    if (nextPath == _lastPlaybackPath && nextPlaying == _lastPlaybackPlaying) {
      return;
    }
    setState(() {
      _lastPlaybackPath = nextPath;
      _lastPlaybackPlaying = nextPlaying;
    });
  }

  Future<void> _openLibrary() async {
    try {
      final database = await LibraryDatabase.open();
      _database = database;
      _musicRoot = await database.loadMusicRoot();
      await _loadFromDatabase();
      if (_tracks.isEmpty || _needsCoverCacheRefresh || _scanRootChanged) {
        await _scanLibrary();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadFromDatabase() async {
    final database = _database;
    if (database == null) {
      return;
    }

    final tracks = await database.loadTracks();
    final folders = await database.loadFolders();
    final albums = await database.loadAlbums();
    final scanState = await database.loadScanState();
    final trackCoverCache = await database.loadTrackCoverCache(tracks);

    if (mounted) {
      setState(() {
        _tracks = tracks;
        _folders = folders;
        _albums = albums;
        _setTrackCoverCache(trackCoverCache, tracks: tracks);
        _scanState = scanState;
        if (_selectedPlaylistPath != null &&
            !folders.any((folder) => folder.path == _selectedPlaylistPath)) {
          _selectedPlaylistPath = null;
        }
        final currentTrackPaths = tracks.map((track) => track.path).toSet();
        final activeAlbum = _activeAlbumPlayback;
        if (activeAlbum != null &&
            (!albums.any(
                  (album) => album.folderPath == activeAlbum.album.folderPath,
                ) ||
                activeAlbum.tracks.any(
                  (track) => !currentTrackPaths.contains(track.path),
                ))) {
          _activeAlbumPlayback = null;
        }
        final activePlaylistPath = _activePlaylistPlayback?.folderPath;
        final activePlaylist = _activePlaylistPlayback;
        if (activePlaylist != null &&
            (!folders.any((folder) => folder.path == activePlaylistPath) ||
                activePlaylist.tracks.any(
                  (track) => !currentTrackPaths.contains(track.path),
                ))) {
          _activePlaylistPlayback = null;
        }
        _loading = false;
      });
      _startBackgroundCoverIndexing(tracks, knownCache: trackCoverCache);
    }
  }

  Future<void> _scanLibrary() async {
    final database = _database;
    if (database == null || _scanning) {
      return;
    }

    _coverIndexer.cancel();
    setState(() {
      _scanning = true;
      _loading = false;
      _error = null;
      _scanProgress = ScanProgress(
        filesSeen: 0,
        tracksParsed: 0,
        currentPath: _musicRoot,
      );
    });

    try {
      final result = await _scanner.scan(
        _musicRoot,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _scanProgress = progress);
          }
        },
      );
      await database.replaceLibrary(result);
      await _loadFromDatabase();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanProgress = null;
        });
      }
    }
  }

  void _handleRescanPressed() {
    _openRescanModal();
    _startRescanDiff();
  }

  void _startRescanDiff({bool full = false}) {
    if (_rescanTask != null || _rescanState.value.phase.isBusy) {
      return;
    }
    _rescanTask = _runRescanDiff(
      full: full,
    ).whenComplete(() => _rescanTask = null);
  }

  Future<void> _runRescanDiff({required bool full}) async {
    final database = _database;
    if (database == null) {
      return;
    }

    List<Track>? rescanResultTracks;
    _coverIndexer.cancel();
    setState(() {
      _scanning = true;
      _error = null;
      _scanProgress = null;
    });
    _rescanState.value = const RescanUiState(
      phase: RescanPhase.loadingDatabase,
      message: 'Loading current library snapshot',
    );

    try {
      final snapshot = await database.loadSnapshot();
      if (!mounted) {
        return;
      }
      _rescanState.value = RescanUiState(
        phase: RescanPhase.scanning,
        message: full ? 'Fully scanning local files' : 'Scanning local files',
      );
      final result = await _scanner.scan(
        _musicRoot,
        previousTracks: full ? null : snapshot.tracks,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          _scanProgress = progress;
          _rescanState.value = _rescanState.value.copyWith(
            progress: progress,
            message: full
                ? 'Fully scanning local files'
                : 'Scanning local files',
          );
          setState(() {});
        },
      );
      rescanResultTracks = result.tracks;
      if (!mounted) {
        return;
      }
      _rescanState.value = _rescanState.value.copyWith(
        phase: RescanPhase.diffing,
        message: 'Comparing scan with database',
        progress: null,
      );
      final diff = diffLibrary(snapshot, result);
      if (!diff.hasChanges) {
        await database.saveScanState(result);
        if (!mounted) {
          return;
        }
        final scanState = await database.loadScanState();
        if (!mounted) {
          return;
        }
        setState(() => _scanState = scanState);
      }
      _rescanState.value = RescanUiState(
        phase: RescanPhase.ready,
        message: diff.hasChanges
            ? 'Review changes before applying'
            : 'Library is up to date',
        diff: diff,
      );
    } catch (error) {
      if (mounted) {
        _rescanState.value = RescanUiState(
          phase: RescanPhase.error,
          message: 'Rescan failed',
          error: error.toString(),
        );
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanProgress = null;
        });
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

  void _openRescanModal() {
    if (_rescanDialogOpen) {
      return;
    }
    _rescanDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return RescanDialog(
          stateListenable: _rescanState,
          trackCoverCacheListenable: _trackCoverCacheListenable,
          onApply: _applyPendingDiff,
          onRescan: () => _startRescanDiff(),
          onFullRescan: () => _startRescanDiff(full: true),
        );
      },
    ).whenComplete(() => _rescanDialogOpen = false);
  }

  Future<void> _applyPendingDiff() async {
    final database = _database;
    final diff = _rescanState.value.diff;
    if (database == null || diff == null || !diff.hasChanges) {
      return;
    }

    final risk = diff.deletionRisk();
    if (risk.isLargeDeletion) {
      final confirmed = await _confirmLargeDeletion(risk);
      if (!mounted || !confirmed) {
        return;
      }
    }

    _rescanState.value = _rescanState.value.copyWith(
      phase: RescanPhase.applying,
      message: 'Applying library changes',
    );
    try {
      await database.applyDiff(diff);
      if (!mounted) {
        return;
      }
      await _loadFromDatabase();
      if (!mounted) {
        return;
      }
      await _playback.stopIfCurrentRemoved(
        diff.removed.map((change) => change.path),
      );
      _rescanState.value = _rescanState.value.copyWith(
        phase: RescanPhase.done,
        message: 'Library refreshed',
      );
    } catch (error) {
      if (mounted) {
        _rescanState.value = _rescanState.value.copyWith(
          phase: RescanPhase.error,
          message: 'Apply failed',
          error: error.toString(),
        );
      }
    }
  }

  Future<void> _handleMusicRootPressed() async {
    final database = _database;
    if (database == null || _scanning) {
      return;
    }

    final nextRoot = await _showMusicRootDialog();
    if (!mounted || nextRoot == null || nextRoot == _musicRoot) {
      return;
    }

    if (!await Directory(nextRoot).exists()) {
      if (mounted) {
        setState(() => _error = 'Music folder does not exist: $nextRoot');
      }
      return;
    }

    await database.saveMusicRoot(nextRoot);
    if (!mounted) {
      return;
    }
    _coverIndexer.cancel();
    setState(() {
      _musicRoot = nextRoot;
      _selectedPlaylistPath = null;
      _error = null;
    });
    await _scanLibrary();
  }

  Future<String?> _showMusicRootDialog() async {
    final controller = TextEditingController(text: _musicRoot);
    try {
      return showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Music folder'),
            content: SizedBox(
              width: 520,
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Folder path',
                  hintText: '~/Music',
                ),
                onSubmitted: (_) =>
                    _submitMusicRootDialog(context, controller.text),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    _submitMusicRootDialog(context, controller.text),
                child: const Text('Save and scan'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  void _submitMusicRootDialog(BuildContext context, String rawPath) {
    final path = normalizeMusicRootPath(rawPath);
    if (path.isEmpty) {
      return;
    }
    Navigator.of(context).pop(path);
  }

  Future<bool> _confirmLargeDeletion(DeletionRisk risk) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm large removal'),
          content: Text(
            'This refresh would remove ${risk.removedCount} tracks '
            '(${(risk.removedRatio * 100).toStringAsFixed(1)}% of the current library). '
            'Check that the drive is mounted and the music root is correct before applying.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Apply anyway'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _playQueueFrom(List<Track> queue, Track track) {
    return _playback.playQueueFrom(queue, track);
  }

  Future<void> _playAlbum(AlbumSummary album, List<Track> tracks) async {
    if (tracks.isEmpty) {
      return;
    }
    setState(() {
      _activeAlbumPlayback = _ActiveAlbumPlayback(album: album, tracks: tracks);
      _activePlaylistPlayback = null;
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _playQueueFrom(tracks, tracks.first);
  }

  Future<void> _playPlaylist(
    FolderSummary folder,
    List<Track> tracks, {
    Track? startTrack,
  }) async {
    if (tracks.isEmpty) {
      return;
    }
    setState(() {
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = _ActivePlaylistPlayback(
        folderPath: folder.path,
        tracks: tracks,
      );
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _playQueueFrom(tracks, startTrack ?? tracks.first);
  }

  Future<void> _playPlaylistShuffled(
    FolderSummary folder,
    List<Track> tracks,
  ) async {
    if (tracks.isEmpty) {
      return;
    }
    final shuffled = tracks.toList(growable: false)..shuffle(math.Random());
    setState(() {
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = _ActivePlaylistPlayback(
        folderPath: folder.path,
        tracks: tracks,
      );
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _playQueueFrom(shuffled, shuffled.first);
  }

  List<FolderSummary> get _playlistFolders =>
      _folders.where((folder) => folder.kind == FolderKind.playlist).toList();

  int get _playlistCount =>
      _folders.where((folder) => folder.kind == FolderKind.playlist).length;

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

  Map<String, List<Track>> get _tracksByFolder => tracksByFolderMap(_tracks);

  @override
  Widget build(BuildContext context) {
    final activeAlbumPlayback = _activeAlbumPlayback;
    final activeAlbumTrack = activeAlbumPlayback == null
        ? null
        : _currentTrackForAlbum(activeAlbumPlayback);
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              LibrarySidebar(
                selected: _view,
                albums: _albums.length,
                playlists: _playlistCount,
                scanState: _scanState,
                musicRoot: _musicRoot,
                scanning: _scanning,
                progress: _scanProgress,
                error: _error,
                onEditMusicRoot: _handleMusicRootPressed,
                onRescan: _handleRescanPressed,
                onSelected: (view) {
                  setState(() {
                    _view = view;
                    _selectedPlaylistPath = null;
                  });
                },
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _buildContent()),
            ],
          ),
          if (activeAlbumPlayback != null)
            Positioned.fill(
              child: AlbumPlaybackView(
                album: activeAlbumPlayback.album,
                tracks: activeAlbumPlayback.tracks,
                currentTrack: activeAlbumTrack,
                playing: activeAlbumTrack != null && _playback.playing,
                onClose: _closeAlbumPlayback,
                onPrevious: () =>
                    unawaited(_playback.skip(-1, activeAlbumPlayback.tracks)),
                onToggle: () => unawaited(
                  _playback.togglePlayPause(activeAlbumPlayback.tracks),
                ),
                onNext: () =>
                    unawaited(_playback.skip(1, activeAlbumPlayback.tracks)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return switch (_view) {
      LibraryView.albums => AlbumGrid(
        albums: _albums,
        tracksByFolder: _tracksByFolder,
        onPlay: _playAlbum,
      ),
      LibraryView.playlists => _buildPlaylistsContent(),
    };
  }

  Widget _buildPlaylistsContent() {
    final selectedPath = _selectedPlaylistPath;
    final selectedFolder = selectedPath == null
        ? null
        : _folders
              .where(
                (folder) =>
                    folder.kind == FolderKind.playlist &&
                    folder.path == selectedPath,
              )
              .firstOrNull;
    if (selectedFolder != null) {
      final tracks = _tracksByFolder[selectedFolder.path] ?? const <Track>[];
      final activePlaylistPlayback = _activePlaylistPlayback;
      final playlistPlaybackActive =
          activePlaylistPlayback?.folderPath == selectedFolder.path &&
          _currentTrackForPlaylist(activePlaylistPlayback!) != null;
      return PlaylistDetail(
        folder: selectedFolder,
        tracks: tracks,
        trackCoverCache: _trackCoverCache,
        playbackActive: playlistPlaybackActive,
        playing: playlistPlaybackActive && _playback.playing,
        onBack: () {
          setState(() => _selectedPlaylistPath = null);
          _restorePlaylistListScrollOffset();
        },
        onPlayAll: tracks.isEmpty
            ? null
            : () => unawaited(_playPlaylist(selectedFolder, tracks)),
        onShuffleAll: tracks.isEmpty
            ? null
            : () => unawaited(_playPlaylistShuffled(selectedFolder, tracks)),
        onPrevious: playlistPlaybackActive
            ? () => unawaited(_playback.skip(-1, activePlaylistPlayback.tracks))
            : null,
        onTogglePlayback: playlistPlaybackActive
            ? () => unawaited(
                _playback.togglePlayPause(activePlaylistPlayback.tracks),
              )
            : null,
        onNext: playlistPlaybackActive
            ? () => unawaited(_playback.skip(1, activePlaylistPlayback.tracks))
            : null,
        onPlayTrack: (track) =>
            unawaited(_playPlaylist(selectedFolder, tracks, startTrack: track)),
      );
    }

    return PlaylistList(
      folders: _playlistFolders,
      tracksByFolder: _tracksByFolder,
      trackCoverCache: _trackCoverCache,
      scrollController: _playlistListScrollController,
      onOpen: _selectPlaylist,
    );
  }

  void _selectPlaylist(FolderSummary folder) {
    _savePlaylistListScrollOffset();
    setState(() => _selectedPlaylistPath = folder.path);
  }

  void _closeAlbumPlayback() {
    setState(() => _activeAlbumPlayback = null);
  }

  Track? _currentTrackForAlbum(_ActiveAlbumPlayback albumPlayback) {
    final currentTrack = _playback.currentTrack;
    if (currentTrack == null) {
      return null;
    }
    return albumPlayback.tracks.any((track) => track.path == currentTrack.path)
        ? currentTrack
        : null;
  }

  Track? _currentTrackForPlaylist(_ActivePlaylistPlayback playlistPlayback) {
    final currentTrack = _playback.currentTrack;
    if (currentTrack == null) {
      return null;
    }
    return playlistPlayback.tracks.any(
          (track) => track.path == currentTrack.path,
        )
        ? currentTrack
        : null;
  }

  void _savePlaylistListScrollOffset() {
    if (_playlistListScrollController.hasClients) {
      _playlistListScrollOffset = _playlistListScrollController.offset;
    }
  }

  void _restorePlaylistListScrollOffset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _selectedPlaylistPath != null ||
          !_playlistListScrollController.hasClients) {
        return;
      }
      final position = _playlistListScrollController.position;
      final target = _playlistListScrollOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _playlistListScrollController.jumpTo(target);
    });
  }

  void _startBackgroundCoverIndexing(
    List<Track> tracks, {
    Map<String, String?>? knownCache,
    bool pruneWhenComplete = true,
  }) {
    final database = _database;
    if (database == null || tracks.isEmpty) {
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
        shouldPause: () => _scanning || !mounted,
        onCacheUpdated: (updates) {
          if (!mounted || updates.isEmpty) {
            return;
          }
          setState(() {
            _setTrackCoverCache({..._trackCoverCache, ...updates});
          });
        },
      );
      if (completed && pruneWhenComplete && mounted && !_scanning) {
        await _pruneUnusedCoverCache(database);
      }
    } catch (_) {
      // Background cover indexing is best-effort and must stay invisible.
    }
  }

  Future<void> _pruneUnusedCoverCache(LibraryDatabase database) async {
    try {
      final referencedPaths = await database.loadReferencedCoverArtPaths();
      await pruneCoverCacheFiles(referencedPaths);
    } catch (_) {
      // Cover pruning is opportunistic and should never affect library use.
    }
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
    _trackCoverCacheListenable.value = nextCache;
  }
}

class _ActiveAlbumPlayback {
  const _ActiveAlbumPlayback({required this.album, required this.tracks});

  final AlbumSummary album;
  final List<Track> tracks;
}

class _ActivePlaylistPlayback {
  const _ActivePlaylistPlayback({
    required this.folderPath,
    required this.tracks,
  });

  final String folderPath;
  final List<Track> tracks;
}
