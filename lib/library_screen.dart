part of 'main.dart';

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
  final _rescanState = ValueNotifier<_RescanUiState>(
    const _RescanUiState(phase: _RescanPhase.idle),
  );

  LibraryDatabase? _database;
  List<Track> _tracks = const [];
  List<FolderSummary> _folders = const [];
  List<AlbumSummary> _albums = const [];
  Map<String, String?> _trackCoverCache = const {};
  Map<String, Object?>? _scanState;
  String _musicRoot = defaultMusicRoot;
  ScanProgress? _scanProgress;
  _LibraryView _view = _LibraryView.tracks;
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
        _trackCoverCache = trackCoverCache;
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

  void _startRescanDiff() {
    if (_rescanTask != null || _rescanState.value.phase.isBusy) {
      return;
    }
    _rescanTask = _runRescanDiff().whenComplete(() => _rescanTask = null);
  }

  Future<void> _runRescanDiff() async {
    final database = _database;
    if (database == null) {
      return;
    }

    _coverIndexer.cancel();
    setState(() {
      _scanning = true;
      _error = null;
      _scanProgress = null;
    });
    _rescanState.value = const _RescanUiState(
      phase: _RescanPhase.loadingDatabase,
      message: 'Loading current library snapshot',
    );

    try {
      final snapshot = await database.loadSnapshot();
      if (!mounted) {
        return;
      }
      _rescanState.value = const _RescanUiState(
        phase: _RescanPhase.scanning,
        message: 'Scanning local files',
      );
      final result = await _scanner.scan(
        _musicRoot,
        previousTracks: snapshot.tracks,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          _scanProgress = progress;
          _rescanState.value = _rescanState.value.copyWith(
            progress: progress,
            message: 'Scanning local files',
          );
          setState(() {});
        },
      );
      if (!mounted) {
        return;
      }
      _rescanState.value = _rescanState.value.copyWith(
        phase: _RescanPhase.diffing,
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
      _rescanState.value = _RescanUiState(
        phase: _RescanPhase.ready,
        message: diff.hasChanges
            ? 'Review changes before applying'
            : 'Library is up to date',
        diff: diff,
      );
    } catch (error) {
      if (mounted) {
        _rescanState.value = _RescanUiState(
          phase: _RescanPhase.error,
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
        _startBackgroundCoverIndexing(_tracks, knownCache: _trackCoverCache);
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
        return _RescanDialog(
          stateListenable: _rescanState,
          onApply: _applyPendingDiff,
          onRescan: _startRescanDiff,
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
      phase: _RescanPhase.applying,
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
        phase: _RescanPhase.done,
        message: 'Library refreshed',
      );
    } catch (error) {
      if (mounted) {
        _rescanState.value = _rescanState.value.copyWith(
          phase: _RescanPhase.error,
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

  Map<String, List<Track>> get _tracksByFolder => _tracksByFolderMap(_tracks);

  @override
  Widget build(BuildContext context) {
    final currentTrack = _playback.currentTrack;
    return Scaffold(
      body: Row(
        children: [
          _LibrarySidebar(
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
                _PlayerBar(
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
      _LibraryView.tracks => _LibraryTrackList(
        tracks: _tracks,
        currentPath: _playback.currentTrack?.path,
        trackCoverCache: _trackCoverCache,
        onPlay: (track) => _playQueueFrom(_tracks, track),
      ),
      _LibraryView.albums => _AlbumGrid(
        albums: _albums,
        tracksByFolder: _tracksByFolder,
        onPlay: (tracks) => _playQueueFrom(tracks, tracks.first),
      ),
      _LibraryView.playlists => _buildPlaylistsContent(),
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
      return _PlaylistDetail(
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

    return _PlaylistList(
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
  }) {
    final database = _database;
    if (database == null || tracks.isEmpty) {
      return;
    }
    unawaited(_runBackgroundCoverIndexing(database, tracks, knownCache));
  }

  Future<void> _runBackgroundCoverIndexing(
    LibraryDatabase database,
    List<Track> tracks,
    Map<String, String?>? knownCache,
  ) async {
    try {
      await _coverIndexer.indexTracks(
        tracks: tracks,
        database: database,
        knownCache: knownCache,
        shouldPause: () => _scanning || !mounted,
        onCacheUpdated: (updates) {
          if (!mounted || updates.isEmpty) {
            return;
          }
          setState(() {
            _trackCoverCache = {..._trackCoverCache, ...updates};
          });
        },
      );
    } catch (_) {
      // Background cover indexing is best-effort and must stay invisible.
    }
  }

  String? _trackArtworkPath(Track track) {
    return _trackCoverCache[track.path] ?? track.coverArtPath;
  }
}
