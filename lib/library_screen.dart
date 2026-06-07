import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'album_views.dart';
import 'artwork_resolver.dart';
import 'cover_cache.dart';
import 'library_database.dart';
import 'library_diff.dart';
import 'library_formatters.dart';
import 'library_sidebar.dart';
import 'library_types.dart';
import 'library_widgets.dart';
import 'models.dart';
import 'music_scanner.dart';
import 'playback_controller.dart';
import 'playlist_cover_indexer.dart';
import 'playlist_views.dart';
import 'rescan_dialog.dart';
import 'track_views.dart';

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
  String _musicRoot = defaultMusicRoot;
  ScanProgress? _scanProgress;
  LibraryView _view = LibraryView.tracks;
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
    if (mounted) {
      setState(() {});
    }
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

  Future<void> _playShuffledQueue(List<Track> queue) {
    if (queue.isEmpty) {
      return Future<void>.value();
    }
    final shuffled = queue.toList(growable: false)..shuffle(math.Random());
    return _playQueueFrom(shuffled, shuffled.first);
  }

  Future<void> _togglePlayPause() {
    return _playback.togglePlayPause(_tracks);
  }

  Future<void> _skip(int delta) {
    return _playback.skip(delta, _tracks);
  }

  Future<void> _seek(Duration position) => _playback.seek(position);

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
    final currentTrack = _playback.currentTrack;
    return Scaffold(
      body: Row(
        children: [
          LibrarySidebar(
            selected: _view,
            tracks: _tracks.length,
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
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildContent()),
                PlayerBar(
                  track: currentTrack,
                  coverArtPath: currentTrack == null
                      ? null
                      : _trackArtworkPath(currentTrack),
                  playing: _playback.playing,
                  position: _playback.position,
                  duration: _playback.duration,
                  onPrevious: () => _skip(-1),
                  onToggle: _togglePlayPause,
                  onNext: () => _skip(1),
                  onSeek: _seek,
                ),
              ],
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
      LibraryView.tracks => LibraryTrackList(
        tracks: _tracks,
        currentPath: _playback.currentTrack?.path,
        trackCoverCache: _trackCoverCache,
        onPlay: (track) => _playQueueFrom(_tracks, track),
      ),
      LibraryView.albums => AlbumGrid(
        albums: _albums,
        tracksByFolder: _tracksByFolder,
        onPlay: (tracks) => _playQueueFrom(tracks, tracks.first),
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
      return PlaylistDetail(
        folder: selectedFolder,
        tracks: tracks,
        currentPath: _playback.currentTrack?.path,
        trackCoverCache: _trackCoverCache,
        onBack: () {
          setState(() => _selectedPlaylistPath = null);
          _restorePlaylistListScrollOffset();
        },
        onPlayAll: tracks.isEmpty
            ? null
            : () => _playQueueFrom(tracks, tracks.first),
        onShuffleAll: tracks.isEmpty ? null : () => _playShuffledQueue(tracks),
        onPlayTrack: (track) => _playQueueFrom(tracks, track),
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

  String? _trackArtworkPath(Track track) {
    return resolveTrackArtwork(track, _trackCoverCache);
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
