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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class _RescanUiState {
  const _RescanUiState({
    required this.phase,
    this.message = '',
    this.progress,
    this.diff,
    this.error,
  });

  final _RescanPhase phase;
  final String message;
  final ScanProgress? progress;
  final LibraryDiff? diff;
  final String? error;

  _RescanUiState copyWith({
    _RescanPhase? phase,
    String? message,
    ScanProgress? progress,
    LibraryDiff? diff,
    String? error,
  }) {
    return _RescanUiState(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      progress: progress,
      diff: diff ?? this.diff,
      error: error,
    );
  }
}

class _RescanDialog extends StatelessWidget {
  const _RescanDialog({
    required this.stateListenable,
    required this.onApply,
    required this.onRetry,
  });

  final ValueListenable<_RescanUiState> stateListenable;
  final Future<void> Function() onApply;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_RescanUiState>(
      valueListenable: stateListenable,
      builder: (context, state, _) {
        final busy = state.phase.isBusy;
        final diff = state.diff;
        return AlertDialog(
          title: const Text('Rescan library'),
          content: SizedBox(
            width: 760,
            height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RescanStatus(state: state),
                const SizedBox(height: 16),
                Expanded(child: _RescanBody(state: state)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: state.phase == _RescanPhase.applying
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (state.phase == _RescanPhase.error)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            FilledButton(
              onPressed:
                  state.phase == _RescanPhase.ready &&
                      !busy &&
                      diff != null &&
                      diff.hasChanges
                  ? onApply
                  : null,
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }
}

class _RescanStatus extends StatelessWidget {
  const _RescanStatus({required this.state});

  final _RescanUiState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = state.progress;
    final diff = state.diff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_phaseIcon(state.phase), color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                state.message.isEmpty
                    ? _phaseLabel(state.phase)
                    : state.message,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        if (state.phase.isBusy) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(value: null, minHeight: 3),
        ],
        if (progress != null) ...[
          const SizedBox(height: 8),
          Text(
            '${progress.tracksParsed} tracks · ${progress.currentPath}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (diff != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              _DiffStat(label: 'Added', value: diff.added.length),
              _DiffStat(label: 'Removed', value: diff.removed.length),
              _DiffStat(label: 'Modified', value: diff.modified.length),
              _DiffStat(label: 'Unchanged', value: diff.unchangedCount),
            ],
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 10),
          Text(state.error!, style: TextStyle(color: scheme.error)),
        ],
      ],
    );
  }

  IconData _phaseIcon(_RescanPhase phase) {
    return switch (phase) {
      _RescanPhase.ready => Icons.fact_check,
      _RescanPhase.done => Icons.check_circle,
      _RescanPhase.error => Icons.error,
      _RescanPhase.applying => Icons.save,
      _ => Icons.sync,
    };
  }

  String _phaseLabel(_RescanPhase phase) {
    return switch (phase) {
      _RescanPhase.idle => 'Ready to rescan',
      _RescanPhase.loadingDatabase => 'Loading current library snapshot',
      _RescanPhase.scanning => 'Scanning local files',
      _RescanPhase.diffing => 'Comparing scan with database',
      _RescanPhase.ready => 'Review changes before applying',
      _RescanPhase.applying => 'Applying library changes',
      _RescanPhase.done => 'Library refreshed',
      _RescanPhase.error => 'Rescan failed',
    };
  }
}

class _DiffStat extends StatelessWidget {
  const _DiffStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value.toString(),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _RescanBody extends StatelessWidget {
  const _RescanBody({required this.state});

  final _RescanUiState state;

  @override
  Widget build(BuildContext context) {
    final diff = state.diff;
    if (state.phase == _RescanPhase.error) {
      return const _EmptyState(message: 'Fix the error and retry the scan');
    }
    if (diff == null) {
      return const _EmptyState(
        message: 'Scanning will continue even if this window is closed',
      );
    }
    if (!diff.hasChanges) {
      return const _EmptyState(message: 'Library is already up to date');
    }
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: 'Added ${diff.added.length}'),
              Tab(text: 'Removed ${diff.removed.length}'),
              Tab(text: 'Modified ${diff.modified.length}'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ChangeList(changes: diff.added),
                _ChangeList(changes: diff.removed),
                _ChangeList(changes: diff.modified),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeList extends StatelessWidget {
  const _ChangeList({required this.changes});

  final List<TrackChange> changes;

  @override
  Widget build(BuildContext context) {
    if (changes.isEmpty) {
      return const _EmptyState(message: 'No tracks in this category');
    }
    return ListView.builder(
      itemCount: changes.length,
      itemBuilder: (context, index) {
        final change = changes[index];
        final track = change.newTrack ?? change.oldTrack!;
        return ListTile(
          dense: true,
          leading: Icon(_changeIcon(change.reason)),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${track.artist} · ${track.album.isEmpty ? track.folderName : track.album}\n${track.path}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  IconData _changeIcon(TrackChangeReason reason) {
    return switch (reason) {
      TrackChangeReason.added => Icons.add_circle,
      TrackChangeReason.removed => Icons.remove_circle,
      TrackChangeReason.fileChanged => Icons.change_circle,
    };
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _scanner = MusicScanner();
  final _player = Player();
  final _searchController = TextEditingController();
  final _rescanState = ValueNotifier<_RescanUiState>(
    const _RescanUiState(phase: _RescanPhase.idle),
  );

  LibraryDatabase? _database;
  List<Track> _tracks = const [];
  List<FolderSummary> _folders = const [];
  List<AlbumSummary> _albums = const [];
  Map<String, Object?>? _scanState;
  ScanProgress? _scanProgress;
  Track? _currentTrack;
  _LibraryView _view = _LibraryView.tracks;
  String? _selectedPlaylistPath;
  List<Track> _playQueue = const [];
  int _queueIndex = -1;
  String _query = '';
  bool _loading = true;
  bool _scanning = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;
  bool _rescanDialogOpen = false;
  Future<void>? _rescanTask;

  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _completedSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;

  @override
  void initState() {
    super.initState();
    _playingSub = _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _playing = playing);
      }
    });
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed) {
        unawaited(_playNextFromQueue());
      }
    });
    _positionSub = _player.stream.position.listen((position) {
      if (mounted) {
        setState(() => _position = position);
      }
    });
    _durationSub = _player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() => _duration = duration);
      }
    });
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    unawaited(_openLibrary());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _rescanState.dispose();
    unawaited(_playingSub.cancel());
    unawaited(_completedSub.cancel());
    unawaited(_positionSub.cancel());
    unawaited(_durationSub.cancel());
    unawaited(_player.dispose());
    unawaited(_database?.close());
    super.dispose();
  }

  Future<void> _openLibrary() async {
    try {
      final database = await LibraryDatabase.open();
      _database = database;
      await _loadFromDatabase();
      if (_tracks.isEmpty || _needsCoverCacheRefresh) {
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

    if (mounted) {
      setState(() {
        _tracks = tracks;
        _folders = folders;
        _albums = albums;
        _scanState = scanState;
        if (_selectedPlaylistPath != null &&
            !folders.any((folder) => folder.path == _selectedPlaylistPath)) {
          _selectedPlaylistPath = null;
        }
        _loading = false;
      });
    }
  }

  Future<void> _scanLibrary() async {
    final database = _database;
    if (database == null || _scanning) {
      return;
    }

    setState(() {
      _scanning = true;
      _loading = false;
      _error = null;
      _scanProgress = const ScanProgress(
        filesSeen: 0,
        tracksParsed: 0,
        currentPath: defaultMusicRoot,
      );
    });

    try {
      final result = await _scanner.scan(
        defaultMusicRoot,
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
    final phase = _rescanState.value.phase;
    final currentDiff = _rescanState.value.diff;
    final canStart =
        phase == _RescanPhase.idle ||
        phase == _RescanPhase.done ||
        phase == _RescanPhase.error ||
        (phase == _RescanPhase.ready && currentDiff?.hasChanges == false);
    if (canStart && _rescanTask == null) {
      _rescanTask = _runRescanDiff().whenComplete(() => _rescanTask = null);
    }
  }

  Future<void> _runRescanDiff() async {
    final database = _database;
    if (database == null) {
      return;
    }

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
        defaultMusicRoot,
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
          onRetry: () {
            _rescanTask ??= _runRescanDiff().whenComplete(
              () => _rescanTask = null,
            );
          },
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
      final current = _currentTrack;
      if (current != null &&
          diff.removed.any((change) => change.path == current.path)) {
        if (mounted) {
          setState(() {
            _playQueue = const [];
            _queueIndex = -1;
            _currentTrack = null;
            _position = Duration.zero;
            _duration = Duration.zero;
          });
        }
        await _player.stop();
      }
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

  Future<void> _playQueueFrom(List<Track> queue, Track track) async {
    if (queue.isEmpty) {
      return;
    }
    final index = queue.indexWhere((candidate) => candidate.path == track.path);
    final nextIndex = index < 0 ? 0 : index;
    final nextTrack = queue[nextIndex];
    setState(() {
      _playQueue = List.unmodifiable(queue);
      _queueIndex = nextIndex;
      _currentTrack = nextTrack;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    await _player.open(Media(nextTrack.path), play: true);
  }

  Future<void> _playNextFromQueue() async {
    if (_playQueue.isEmpty || _queueIndex < 0) {
      return;
    }
    final nextIndex = _queueIndex + 1;
    if (nextIndex >= _playQueue.length) {
      return;
    }
    await _playQueueAt(nextIndex);
  }

  Future<void> _playQueueAt(int index) async {
    if (index < 0 || index >= _playQueue.length) {
      return;
    }
    final track = _playQueue[index];
    setState(() {
      _queueIndex = index;
      _currentTrack = track;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    await _player.open(Media(track.path), play: true);
  }

  Future<void> _togglePlayPause() async {
    if (_currentTrack == null) {
      final first = _filteredTracks.isEmpty ? null : _filteredTracks.first;
      if (first != null) {
        await _playQueueFrom(_filteredTracks, first);
      }
      return;
    }
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _skip(int delta) async {
    if (_playQueue.isNotEmpty && _queueIndex >= 0) {
      await _playQueueAt(_queueIndex + delta);
      return;
    }
    final source = _filteredTracks.isEmpty ? _tracks : _filteredTracks;
    if (source.isEmpty) {
      return;
    }
    final current = _currentTrack;
    final currentIndex = current == null
        ? -1
        : source.indexWhere((track) => track.path == current.path);
    final nextIndex = currentIndex < 0
        ? 0
        : (currentIndex + delta).clamp(0, source.length - 1);
    await _playQueueFrom(source, source[nextIndex]);
  }

  Future<void> _seek(Duration position) async {
    await _player.seek(position);
  }

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

  Map<String, List<Track>> get _tracksByFolder => _tracksByFolderMap(_tracks);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _LibrarySidebar(
            selected: _view,
            tracks: _tracks.length,
            albums: _albums.length,
            playlists: _playlistCount,
            scanState: _scanState,
            scanning: _scanning,
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
                  track: _currentTrack,
                  playing: _playing,
                  position: _position,
                  duration: _duration,
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
      _LibraryView.tracks => _TrackList(
        tracks: _filteredTracks,
        currentPath: _currentTrack?.path,
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
        currentPath: _currentTrack?.path,
        onBack: () => setState(() => _selectedPlaylistPath = null),
        onPlayAll: tracks.isEmpty
            ? null
            : () => _playQueueFrom(tracks, tracks.first),
        onPlayTrack: (track) => _playQueueFrom(tracks, track),
      );
    }

    return _PlaylistList(
      folders: _playlistFolders,
      tracksByFolder: _tracksByFolder,
      onOpen: (folder) => setState(() => _selectedPlaylistPath = folder.path),
      onPlay: (tracks) => _playQueueFrom(tracks, tracks.first),
    );
  }
}

class _LibrarySidebar extends StatelessWidget {
  const _LibrarySidebar({
    required this.selected,
    required this.tracks,
    required this.albums,
    required this.playlists,
    required this.scanState,
    required this.scanning,
    required this.onSelected,
  });

  final _LibraryView selected;
  final int tracks;
  final int albums;
  final int playlists;
  final Map<String, Object?>? scanState;
  final bool scanning;
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
              child: _LibraryStats(scanState: scanState, scanning: scanning),
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
  const _LibraryStats({required this.scanState, required this.scanning});

  final Map<String, Object?>? scanState;
  final bool scanning;

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
            ],
          ),
          const SizedBox(height: 8),
          Text(
            defaultMusicRoot,
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

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.tracks,
    required this.currentPath,
    required this.onPlay,
    this.showArtwork = true,
  });

  final List<Track> tracks;
  final String? currentPath;
  final ValueChanged<Track> onPlay;
  final bool showArtwork;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const _EmptyState(message: 'No tracks found');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final track = tracks[index];
        final selected = track.path == currentPath;
        return _TrackRow(
          index: index,
          track: track,
          selected: selected,
          showArtwork: showArtwork,
          onTap: () => onPlay(track),
        );
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.index,
    required this.track,
    required this.selected,
    required this.showArtwork,
    required this.onTap,
  });

  final int index;
  final Track track;
  final bool selected;
  final bool showArtwork;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.65)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (showArtwork) ...[
              _Artwork(
                path: track.coverArtPath,
                size: 42,
                icon: Icons.music_note,
              ),
              const SizedBox(width: 12),
            ] else ...[
              SizedBox(
                width: 42,
                child: Text(
                  (index + 1).toString().padLeft(2, '0'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
        final columns = math.max(2, (width / 190).floor());
        return GridView.builder(
          padding: const EdgeInsets.all(22),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 18,
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
    required this.onOpen,
    required this.onPlay,
  });

  final List<FolderSummary> folders;
  final Map<String, List<Track>> tracksByFolder;
  final ValueChanged<FolderSummary> onOpen;
  final ValueChanged<List<Track>> onPlay;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return const _EmptyState(message: 'No playlist folders detected');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
      itemCount: folders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final folder = folders[index];
        final tracks = tracksByFolder[folder.path] ?? const <Track>[];
        return _PlaylistRow(
          index: index,
          folder: folder,
          onOpen: () => onOpen(folder),
          onPlay: tracks.isEmpty ? null : () => onPlay(tracks),
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
    required this.onBack,
    required this.onPlayAll,
    required this.onPlayTrack,
  });

  final FolderSummary folder;
  final List<Track> tracks;
  final String? currentPath;
  final VoidCallback onBack;
  final VoidCallback? onPlayAll;
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
                    Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
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
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: onPlayAll,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _TrackList(
            tracks: tracks,
            currentPath: currentPath,
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
    required this.index,
    required this.folder,
    required this.onOpen,
    required this.onPlay,
  });

  final int index;
  final FolderSummary folder;
  final VoidCallback onOpen;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onOpen,
      child: Container(
        height: 92,
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                'P${(index + 1).toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _Artwork(
              path: folder.coverArtPath,
              size: 62,
              icon: Icons.queue_music,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
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
            const SizedBox(width: 12),
            IconButton.filledTonal(
              tooltip: 'Play playlist',
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow),
            ),
          ],
        ),
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

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({
    required this.track,
    required this.playing,
    required this.position,
    required this.duration,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.onSeek,
  });

  final Track? track;
  final bool playing;
  final Duration position;
  final Duration duration;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final durationMs = math.max(1, duration.inMilliseconds);
    final positionMs = position.inMilliseconds.clamp(0, durationMs).toDouble();
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
          color: scheme.surface,
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Artwork(
              path: track?.coverArtPath,
              size: 56,
              icon: Icons.music_note,
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 3,
              child: _TwoLineText(
                title: track?.title ?? 'Nothing playing',
                subtitle: track == null
                    ? 'Select a local track'
                    : '${track!.artist} · ${track!.folderName}',
              ),
            ),
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Previous',
                  onPressed: track == null ? null : onPrevious,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton.filled(
                  tooltip: playing ? 'Pause' : 'Play',
                  onPressed: onToggle,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: track == null ? null : onNext,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 5,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 42, child: Text(_formatDuration(position))),
                  Expanded(
                    child: Slider(
                      value: positionMs,
                      max: durationMs.toDouble(),
                      onChanged: track == null
                          ? null
                          : (value) {
                              onSeek(Duration(milliseconds: value.round()));
                            },
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      _formatDuration(duration),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.path,
    required this.size,
    required this.icon,
    this.radius = 8,
  });

  final String? path;
  final double size;
  final IconData icon;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = _ArtworkPlaceholder(icon: icon, radius: radius);
    final imagePath = path;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: imagePath == null || imagePath.isEmpty
          ? placeholder
          : Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              cacheWidth: size.isFinite ? (size * 2).round() : 320,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );

    if (size.isFinite) {
      return SizedBox.square(dimension: size, child: image);
    }

    return AspectRatio(aspectRatio: 1, child: image);
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.icon, required this.radius});

  final IconData icon;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: scheme.onSurfaceVariant),
    );
  }
}

class _TwoLineText extends StatelessWidget {
  const _TwoLineText({
    required this.title,
    required this.subtitle,
    this.selected = false,
  });

  final String title;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: Theme.of(context).textTheme.titleMedium),
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
