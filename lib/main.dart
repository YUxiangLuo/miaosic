import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'library_database.dart';
import 'library_diff.dart';
import 'models.dart';
import 'music_scanner.dart';
import 'playback_controller.dart';
import 'playlist_cover_indexer.dart';

part 'library_widgets.dart';
part 'rescan_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  imageCache.maximumSize = 1600;
  imageCache.maximumSizeBytes = 256 * 1024 * 1024;
  MediaKit.ensureInitialized();
  runApp(const MiaosicApp());
}

class MiaosicApp extends StatelessWidget {
  const MiaosicApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff246b5b);
    return MaterialApp(
      title: 'Miaosic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xfff7f7f4),
        useMaterial3: true,
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xffeeeeea),
          indicatorColor: Color(0xffd8ebe3),
          selectedIconTheme: IconThemeData(color: seed),
          selectedLabelTextStyle: TextStyle(
            color: seed,
            fontWeight: FontWeight.w700,
          ),
        ),
        sliderTheme: const SliderThemeData(trackHeight: 3),
      ),
      home: const LibraryScreen(),
    );
  }
}

enum _LibraryView {
  tracks('Tracks', Icons.music_note),
  albums('Albums', Icons.album),
  playlists('Playlists', Icons.queue_music);

  const _LibraryView(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum _RescanPhase {
  idle,
  loadingDatabase,
  scanning,
  diffing,
  ready,
  applying,
  done,
  error;

  bool get isBusy {
    return this == _RescanPhase.loadingDatabase ||
        this == _RescanPhase.scanning ||
        this == _RescanPhase.diffing ||
        this == _RescanPhase.applying;
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _scanner = MusicScanner();
  final _playback = PlaybackController();
  final _coverIndexer = TrackCoverIndexer();
  final _searchController = TextEditingController();
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
  String _query = '';
  bool _loading = true;
  bool _scanning = false;
  String? _error;
  bool _rescanDialogOpen = false;
  Future<void>? _rescanTask;

  @override
  void initState() {
    super.initState();
    _playback.addListener(_handlePlaybackChanged);
    _searchController.addListener(_handleSearchChanged);
    unawaited(_openLibrary());
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  void _handleSearchChanged() {
    setState(() => _query = _searchController.text.trim().toLowerCase());
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
    return _playback.togglePlayPause(_filteredTracks);
  }

  Future<void> _skip(int delta) {
    final source = _filteredTracks.isEmpty ? _tracks : _filteredTracks;
    return _playback.skip(delta, source);
  }

  Future<void> _seek(Duration position) => _playback.seek(position);

  List<Track> get _filteredTracks {
    if (_query.isEmpty) {
      return _tracks;
    }
    return _tracks.where((track) {
      final haystack =
          '${track.title} ${track.artist} ${track.album} ${track.folderName}'
              .toLowerCase();
      return haystack.contains(_query);
    }).toList();
  }

  List<AlbumSummary> get _filteredAlbums {
    if (_query.isEmpty) {
      return _albums;
    }
    return _albums.where((album) {
      return '${album.title} ${album.albumArtist}'.toLowerCase().contains(
        _query,
      );
    }).toList();
  }

  List<FolderSummary> get _playlistFolders {
    final folders = _folders.where(
      (folder) => folder.kind == FolderKind.playlist,
    );
    if (_query.isEmpty) {
      return folders.toList();
    }
    return folders
        .where((folder) => folder.name.toLowerCase().contains(_query))
        .toList();
  }

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
            onEditMusicRoot: _handleMusicRootPressed,
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
                _LibraryToolbar(
                  view: _view,
                  controller: _searchController,
                  scanning: _scanning,
                  progress: _scanProgress,
                  error: _error,
                  onRescan: _handleRescanPressed,
                ),
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
        tracks: _filteredTracks,
        currentPath: _playback.currentTrack?.path,
        trackCoverCache: _trackCoverCache,
        onPlay: (track) => _playQueueFrom(_filteredTracks, track),
      ),
      _LibraryView.albums => _AlbumGrid(
        albums: _filteredAlbums,
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

class _LibrarySidebar extends StatelessWidget {
  const _LibrarySidebar({
    required this.selected,
    required this.tracks,
    required this.albums,
    required this.playlists,
    required this.scanState,
    required this.musicRoot,
    required this.scanning,
    required this.onEditMusicRoot,
    required this.onSelected,
  });

  final _LibraryView selected;
  final int tracks;
  final int albums;
  final int playlists;
  final Map<String, Object?>? scanState;
  final String musicRoot;
  final bool scanning;
  final VoidCallback onEditMusicRoot;
  final ValueChanged<_LibraryView> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 212,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.equalizer, color: scheme.onPrimary),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Miaosic',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            for (final view in _LibraryView.values)
              _SidebarItem(
                view: view,
                selected: selected == view,
                count: switch (view) {
                  _LibraryView.tracks => tracks,
                  _LibraryView.albums => albums,
                  _LibraryView.playlists => playlists,
                },
                onTap: () => onSelected(view),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: _LibraryStats(
                scanState: scanState,
                musicRoot: musicRoot,
                scanning: scanning,
                onEditMusicRoot: onEditMusicRoot,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.view,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final _LibraryView view;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                view.icon,
                size: 20,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  view.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              Text(
                count.toString(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryStats extends StatelessWidget {
  const _LibraryStats({
    required this.scanState,
    required this.musicRoot,
    required this.scanning,
    required this.onEditMusicRoot,
  });

  final Map<String, Object?>? scanState;
  final String musicRoot;
  final bool scanning;
  final VoidCallback onEditMusicRoot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scannedAt = scanState?['scanned_at_ms'] as int?;
    final elapsedMs = scanState?['elapsed_ms'] as int?;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                scanning ? Icons.sync : Icons.storage,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                scanning ? 'Scanning' : 'Library',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Change music folder',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                onPressed: scanning ? null : onEditMusicRoot,
                icon: const Icon(Icons.edit, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            musicRoot,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            scannedAt == null
                ? 'No scan yet'
                : 'Last scan ${_formatDate(scannedAt)} · ${_formatElapsed(elapsedMs)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({
    required this.view,
    required this.controller,
    required this.scanning,
    required this.progress,
    required this.error,
    required this.onRescan,
  });

  final _LibraryView view;
  final TextEditingController controller;
  final bool scanning;
  final ScanProgress? progress;
  final String? error;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        view.label,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search local library',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: scheme.surface,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  tooltip: 'Rescan library',
                  onPressed: scanning ? null : onRescan,
                  icon: scanning
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            if (scanning || error != null) ...[
              const SizedBox(height: 12),
              if (scanning) LinearProgressIndicator(value: null, minHeight: 3),
              if (progress != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${progress!.tracksParsed} tracks · ${progress!.currentPath}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              if (error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(error!, style: TextStyle(color: scheme.error)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    return switch (view) {
      _LibraryView.tracks => 'Fast local browsing for the whole library',
      _LibraryView.albums => 'Album folders detected from local metadata',
      _LibraryView.playlists =>
        'Playlist-like folders kept separate from albums',
    };
  }
}

class _PlaylistTrackList extends StatelessWidget {
  const _PlaylistTrackList({
    required this.tracks,
    required this.currentPath,
    required this.onPlay,
    this.trackCoverCache = const {},
    this.showArtwork = true,
  });

  final List<Track> tracks;
  final String? currentPath;
  final ValueChanged<Track> onPlay;
  final Map<String, String?> trackCoverCache;
  final bool showArtwork;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const _EmptyState(message: 'No tracks found');
    }

    final leftPadding = showArtwork ? 18.0 : 60.0;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(leftPadding, 14, 18, 18),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final track = tracks[index];
        final selected = track.path == currentPath;
        final trackCoverPath = trackCoverCache[track.path];
        return _PlaylistTrackRow(
          index: index,
          track: track,
          selected: selected,
          showArtwork: showArtwork,
          artworkPath: showArtwork
              ? trackCoverPath ?? track.coverArtPath
              : trackCoverPath,
          onTap: () => onPlay(track),
        );
      },
    );
  }
}

class _LibraryTrackList extends StatelessWidget {
  const _LibraryTrackList({
    required this.tracks,
    required this.currentPath,
    required this.trackCoverCache,
    required this.onPlay,
  });

  final List<Track> tracks;
  final String? currentPath;
  final Map<String, String?> trackCoverCache;
  final ValueChanged<Track> onPlay;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const _EmptyState(message: 'No tracks found');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 18.0;
        const spacing = 10.0;
        const cardHeight = 76.0;
        final availableWidth = math.max(
          1.0,
          constraints.maxWidth - horizontalPadding * 2,
        );
        final columns = math.max(1, (availableWidth / 320).floor());
        final cardWidth = (availableWidth - spacing * (columns - 1)) / columns;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            18,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: cardWidth / cardHeight,
          ),
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return _LibraryTrackTile(
              track: track,
              artworkPath: trackCoverCache[track.path] ?? track.coverArtPath,
              selected: track.path == currentPath,
              onTap: () => onPlay(track),
            );
          },
        );
      },
    );
  }
}

class _LibraryTrackTile extends StatelessWidget {
  const _LibraryTrackTile({
    required this.track,
    required this.artworkPath,
    required this.selected,
    required this.onTap,
  });

  final Track track;
  final String? artworkPath;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.65)
              : scheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _Artwork(path: artworkPath, size: 56, icon: Icons.music_note),
            const SizedBox(width: 10),
            Expanded(
              child: _LibraryTrackText(
                title: track.title,
                artist: track.artist,
                selected: selected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryTrackText extends StatelessWidget {
  const _LibraryTrackText({
    required this.title,
    required this.artist,
    required this.selected,
  });

  final String title;
  final String artist;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PlaylistTrackRow extends StatelessWidget {
  const _PlaylistTrackRow({
    required this.index,
    required this.track,
    required this.selected,
    required this.showArtwork,
    required this.artworkPath,
    required this.onTap,
  });

  final int index;
  final Track track;
  final bool selected;
  final bool showArtwork;
  final String? artworkPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.65)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (showArtwork || artworkPath != null) ...[
              _Artwork(path: artworkPath, size: 50, icon: Icons.music_note),
              const SizedBox(width: 14),
            ] else ...[
              SizedBox(
                width: 50,
                child: Text(
                  (index + 1).toString().padLeft(2, '0'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              flex: 5,
              child: _TwoLineText(
                title: track.title,
                subtitle: track.artist,
                selected: selected,
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                track.album.isEmpty ? track.folderName : track.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                _formatDurationMs(track.durationMs),
                textAlign: TextAlign.right,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({
    required this.albums,
    required this.tracksByFolder,
    required this.onPlay,
  });

  final List<AlbumSummary> albums;
  final Map<String, List<Track>> tracksByFolder;
  final ValueChanged<List<Track>> onPlay;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const _EmptyState(message: 'No album folders detected');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = math.min(6, math.max(2, (width / 190).floor()));
        return GridView.builder(
          padding: const EdgeInsets.all(22),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 22,
            mainAxisSpacing: 24,
            childAspectRatio: 0.72,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            final tracks = tracksByFolder[album.folderPath] ?? const <Track>[];
            return _AlbumTile(
              album: album,
              onTap: tracks.isEmpty ? null : () => onPlay(tracks),
            );
          },
        );
      },
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.album, required this.onTap});

  final AlbumSummary album;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Artwork(
              path: album.coverArtPath,
              size: double.infinity,
              icon: Icons.album,
              radius: 8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            album.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            '${album.albumArtist}${album.year == null ? '' : ' · ${album.year}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          Text(
            '${album.trackCount} tracks',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PlaylistList extends StatelessWidget {
  const _PlaylistList({
    required this.folders,
    required this.tracksByFolder,
    required this.trackCoverCache,
    required this.scrollController,
    required this.onOpen,
  });

  final List<FolderSummary> folders;
  final Map<String, List<Track>> tracksByFolder;
  final Map<String, String?> trackCoverCache;
  final ScrollController scrollController;
  final ValueChanged<FolderSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return const _EmptyState(message: 'No playlist folders detected');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 22.0;
        const spacing = 14.0;
        final availableWidth = math.max(
          1.0,
          constraints.maxWidth - horizontalPadding * 2,
        );
        final columns = math.min(
          4,
          math.max(1, (availableWidth / 440).floor()),
        );
        final cardWidth = math.max(
          1.0,
          (availableWidth - spacing * (columns - 1)) / columns,
        );
        const cardHeight = 220.0;
        return GridView.builder(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            16,
            horizontalPadding,
            22,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: cardWidth / cardHeight,
          ),
          itemCount: folders.length,
          itemBuilder: (context, index) {
            final folder = folders[index];
            final tracks = tracksByFolder[folder.path] ?? const <Track>[];
            return _PlaylistRow(
              folder: folder,
              tracks: tracks,
              trackCoverCache: trackCoverCache,
              onOpen: () => onOpen(folder),
            );
          },
        );
      },
    );
  }
}

class _PlaylistDetail extends StatelessWidget {
  const _PlaylistDetail({
    required this.folder,
    required this.tracks,
    required this.currentPath,
    required this.trackCoverCache,
    required this.onBack,
    required this.onPlayAll,
    required this.onShuffleAll,
    required this.onPlayTrack,
  });

  final FolderSummary folder;
  final List<Track> tracks;
  final String? currentPath;
  final Map<String, String?> trackCoverCache;
  final VoidCallback onBack;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;
  final ValueChanged<Track> onPlayTrack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back to playlists',
                onPressed: onBack,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 10),
              _Artwork(
                path: folder.coverArtPath,
                size: 76,
                icon: Icons.queue_music,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          fit: FlexFit.loose,
                          child: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: onPlayAll,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: onShuffleAll,
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Shuffle'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _PlaylistMetric(
                          icon: Icons.music_note,
                          label: '${folder.trackCount} tracks',
                        ),
                        _PlaylistMetric(
                          icon: Icons.album,
                          label: '${folder.albumCount} albums',
                        ),
                        _PlaylistMetric(
                          icon: Icons.person,
                          label: '${folder.artistCount} artists',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _PlaylistTrackList(
            tracks: tracks,
            currentPath: currentPath,
            trackCoverCache: trackCoverCache,
            showArtwork: false,
            onPlay: onPlayTrack,
          ),
        ),
      ],
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.folder,
    required this.tracks,
    required this.trackCoverCache,
    required this.onOpen,
  });

  final FolderSummary folder;
  final List<Track> tracks;
  final Map<String, String?> trackCoverCache;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverPaths = _playlistCoverPaths();
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: _buildContent(context, scheme, coverPaths),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme scheme,
    List<String> coverPaths,
  ) {
    final previewTracks = tracks.take(3).toList(growable: false);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlaylistCoverCollage(coverPaths: coverPaths),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 8, children: _playlistMetrics()),
              const Spacer(),
              if (previewTracks.isNotEmpty) ...[
                for (final track in previewTracks)
                  _PlaylistPreviewTrack(track: track),
              ] else
                Text(
                  'No tracks found',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _playlistMetrics() {
    return [
      _PlaylistMetric(
        icon: Icons.music_note,
        label: '${folder.trackCount} tracks',
      ),
      _PlaylistMetric(icon: Icons.album, label: '${folder.albumCount} albums'),
      _PlaylistMetric(
        icon: Icons.person,
        label: '${folder.artistCount} artists',
      ),
    ];
  }

  List<String> _playlistCoverPaths() {
    final paths = <String>[];
    for (final track in tracks) {
      final path = trackCoverCache[track.path] ?? track.coverArtPath;
      if (path != null && path.isNotEmpty && !paths.contains(path)) {
        paths.add(path);
      }
      if (paths.length >= 4) {
        return paths;
      }
    }
    final folderCover = folder.coverArtPath;
    if (folderCover != null && folderCover.isNotEmpty) {
      paths.add(folderCover);
    }
    return paths;
  }
}

class _PlaylistCoverCollage extends StatelessWidget {
  const _PlaylistCoverCollage({required this.coverPaths});

  final List<String> coverPaths;

  @override
  Widget build(BuildContext context) {
    final paths = coverPaths.take(4).toList(growable: false);
    return SizedBox.square(
      dimension: 188,
      child: ClipRRect(
        child: paths.length <= 1
            ? _Artwork(
                path: paths.isEmpty ? null : paths.first,
                size: double.infinity,
                icon: Icons.queue_music,
                radius: 0,
              )
            : _CoverGrid(paths: paths),
      ),
    );
  }
}

class _CoverGrid extends StatelessWidget {
  const _CoverGrid({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final padded = paths.toList(growable: true);
    while (padded.length < 4) {
      padded.add(paths.last);
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _Artwork(
                  path: padded[0],
                  size: double.infinity,
                  icon: Icons.music_note,
                  radius: 0,
                ),
              ),
              Expanded(
                child: _Artwork(
                  path: padded[1],
                  size: double.infinity,
                  icon: Icons.music_note,
                  radius: 0,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _Artwork(
                  path: padded[2],
                  size: double.infinity,
                  icon: Icons.music_note,
                  radius: 0,
                ),
              ),
              Expanded(
                child: _Artwork(
                  path: padded[3],
                  size: double.infinity,
                  icon: Icons.music_note,
                  radius: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaylistPreviewTrack extends StatelessWidget {
  const _PlaylistPreviewTrack({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '${track.title} · ${track.artist}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _PlaylistMetric extends StatelessWidget {
  const _PlaylistMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

Map<String, List<Track>> _tracksByFolderMap(List<Track> tracks) {
  final grouped = <String, List<Track>>{};
  for (final track in tracks) {
    grouped.putIfAbsent(track.folderPath, () => []).add(track);
  }
  return grouped;
}

String _formatDate(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${date.year}-${_two(date.month)}-${_two(date.day)}';
}

String _formatElapsed(int? ms) {
  if (ms == null) {
    return '-';
  }
  return '${(ms / 1000).toStringAsFixed(1)}s';
}

String _formatDurationMs(int? durationMs) {
  if (durationMs == null || durationMs <= 0) {
    return '-';
  }
  return _formatDuration(Duration(milliseconds: durationMs));
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _two(int value) => value.toString().padLeft(2, '0');
