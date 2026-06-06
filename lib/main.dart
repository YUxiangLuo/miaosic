import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import 'library_database.dart';
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

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _scanner = MusicScanner();
  final _player = Player();
  final _searchController = TextEditingController();

  LibraryDatabase? _database;
  List<Track> _tracks = const [];
  List<FolderSummary> _folders = const [];
  List<AlbumSummary> _albums = const [];
  Map<String, Object?>? _scanState;
  ScanProgress? _scanProgress;
  Track? _currentTrack;
  _LibraryView _view = _LibraryView.tracks;
  String _query = '';
  bool _loading = true;
  bool _scanning = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  late final StreamSubscription<bool> _playingSub;
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
    unawaited(_playingSub.cancel());
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

  Future<void> _playTrack(Track track) async {
    setState(() {
      _currentTrack = track;
      _position = Duration.zero;
    });
    await _player.open(Media(track.path), play: true);
  }

  Future<void> _togglePlayPause() async {
    if (_currentTrack == null) {
      final first = _filteredTracks.isEmpty ? null : _filteredTracks.first;
      if (first != null) {
        await _playTrack(first);
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
    if (_tracks.isEmpty) {
      return;
    }
    final source = _filteredTracks.isEmpty ? _tracks : _filteredTracks;
    final current = _currentTrack;
    final currentIndex = current == null
        ? -1
        : source.indexWhere((track) => track.path == current.path);
    final nextIndex = currentIndex < 0
        ? 0
        : (currentIndex + delta).clamp(0, source.length - 1);
    await _playTrack(source[nextIndex]);
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
            onSelected: (view) => setState(() => _view = view),
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
                  onRescan: _scanLibrary,
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
        onPlay: _playTrack,
      ),
      _LibraryView.albums => _AlbumGrid(
        albums: _filteredAlbums,
        tracksByFolder: _tracksByFolder,
        onPlay: _playTrack,
      ),
      _LibraryView.playlists => _PlaylistList(
        folders: _playlistFolders,
        tracksByFolder: _tracksByFolder,
        onPlay: _playTrack,
      ),
    };
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
  });

  final List<Track> tracks;
  final String? currentPath;
  final ValueChanged<Track> onPlay;

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
          track: track,
          selected: selected,
          onTap: () => onPlay(track),
        );
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.selected,
    required this.onTap,
  });

  final Track track;
  final bool selected;
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
            _Artwork(
              path: track.coverArtPath,
              size: 42,
              icon: Icons.music_note,
            ),
            const SizedBox(width: 12),
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
  final ValueChanged<Track> onPlay;

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
            final firstTrack = tracksByFolder[album.folderPath]?.firstOrNull;
            return _AlbumTile(
              album: album,
              onTap: firstTrack == null ? null : () => onPlay(firstTrack),
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
    required this.onPlay,
  });

  final List<FolderSummary> folders;
  final Map<String, List<Track>> tracksByFolder;
  final ValueChanged<Track> onPlay;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return const _EmptyState(message: 'No playlist folders detected');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
      itemCount: folders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final folder = folders[index];
        final firstTrack = tracksByFolder[folder.path]?.firstOrNull;
        return _PlaylistRow(
          folder: folder,
          onTap: firstTrack == null ? null : () => onPlay(firstTrack),
        );
      },
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.folder, required this.onTap});

  final FolderSummary folder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 74,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _Artwork(
              path: folder.coverArtPath,
              size: 54,
              icon: Icons.queue_music,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _TwoLineText(
                title: folder.name,
                subtitle:
                    '${folder.trackCount} tracks · ${folder.albumCount} albums · ${folder.artistCount} artists',
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${(folder.confidence * 100).round()}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
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
          children: [
            _Artwork(
              path: track?.coverArtPath,
              size: 56,
              icon: Icons.music_note,
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 4,
              child: _TwoLineText(
                title: track?.title ?? 'Nothing playing',
                subtitle: track == null
                    ? 'Select a local track'
                    : '${track!.artist} · ${track!.folderName}',
              ),
            ),
            Expanded(
              flex: 5,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                  Row(
                    children: [
                      SizedBox(
                        width: 42,
                        child: Text(_formatDuration(position)),
                      ),
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
                ],
              ),
            ),
            const Spacer(),
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
