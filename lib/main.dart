import 'dart:async';

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
    return MaterialApp(
      title: 'Miaosic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff246b5b),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        listTileTheme: const ListTileThemeData(dense: true),
      ),
      home: const LibraryScreen(),
    );
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

  LibraryDatabase? _database;
  List<Track> _tracks = const [];
  List<FolderSummary> _folders = const [];
  List<AlbumSummary> _albums = const [];
  Map<String, Object?>? _scanState;
  ScanProgress? _scanProgress;
  Track? _currentTrack;
  String _query = '';
  bool _loading = true;
  bool _scanning = false;
  bool _playing = false;
  String? _error;

  late final StreamSubscription<bool> _playingSub;

  @override
  void initState() {
    super.initState();
    _playingSub = _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _playing = playing);
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
    unawaited(_player.dispose());
    unawaited(_database?.close());
    super.dispose();
  }

  Future<void> _openLibrary() async {
    try {
      final database = await LibraryDatabase.open();
      _database = database;
      await _loadFromDatabase();
      if (_tracks.isEmpty) {
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
    setState(() => _currentTrack = track);
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
    final current = _currentTrack;
    final source = _filteredTracks.isEmpty ? _tracks : _filteredTracks;
    final currentIndex = current == null
        ? -1
        : source.indexWhere((track) => track.path == current.path);
    final nextIndex = currentIndex < 0
        ? 0
        : (currentIndex + delta).clamp(0, source.length - 1);
    await _playTrack(source[nextIndex]);
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Miaosic'),
          actions: [
            IconButton(
              tooltip: 'Rescan library',
              onPressed: _scanning ? null : _scanLibrary,
              icon: _scanning
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Tracks ${_tracks.length}'),
              Tab(text: 'Albums ${_albums.length}'),
              Tab(text: 'Playlists $_playlistCount'),
            ],
          ),
        ),
        body: Column(
          children: [
            _StatusHeader(
              databasePath: _database?.path,
              scanState: _scanState,
              progress: _scanProgress,
              scanning: _scanning,
              error: _error,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search local library',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _TrackList(
                          tracks: _filteredTracks,
                          currentPath: _currentTrack?.path,
                          onPlay: _playTrack,
                        ),
                        _AlbumList(
                          albums: _filteredAlbums,
                          tracks: _tracks,
                          onPlay: _playTrack,
                        ),
                        _FolderList(
                          folders: _playlistFolders,
                          tracks: _tracks,
                          onPlay: _playTrack,
                        ),
                      ],
                    ),
            ),
            _PlayerBar(
              track: _currentTrack,
              playing: _playing,
              onPrevious: () => _skip(-1),
              onToggle: _togglePlayPause,
              onNext: () => _skip(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.databasePath,
    required this.scanState,
    required this.progress,
    required this.scanning,
    required this.error,
  });

  final String? databasePath;
  final Map<String, Object?>? scanState;
  final ScanProgress? progress;
  final bool scanning;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scannedAtMs = scanState?['scanned_at_ms'] as int?;
    final elapsedMs = scanState?['elapsed_ms'] as int?;
    final status = scanning
        ? 'Scanning ${progress?.tracksParsed ?? 0} files'
        : scanState == null
        ? 'No scan yet'
        : 'Last scan ${_formatDate(scannedAtMs)} in ${_formatElapsed(elapsedMs)}';

    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _InfoChip(icon: Icons.folder, text: defaultMusicRoot),
              if (databasePath != null)
                _InfoChip(icon: Icons.storage, text: databasePath!),
              _InfoChip(icon: Icons.sync, text: status),
            ],
          ),
          if (progress != null && scanning) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: null, minHeight: 3),
            const SizedBox(height: 4),
            Text(
              progress!.currentPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }

  String _formatDate(int? ms) {
    if (ms == null) {
      return '-';
    }
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${date.year}-${_two(date.month)}-${_two(date.day)} ${_two(date.hour)}:${_two(date.minute)}';
  }

  String _formatElapsed(int? ms) {
    if (ms == null) {
      return '-';
    }
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
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

    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final selected = track.path == currentPath;
        return ListTile(
          selected: selected,
          leading: Icon(selected ? Icons.graphic_eq : Icons.music_note),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${track.artist} · ${track.album.isEmpty ? track.folderName : track.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(_formatDuration(track.durationMs)),
          onTap: () => onPlay(track),
        );
      },
    );
  }
}

class _AlbumList extends StatelessWidget {
  const _AlbumList({
    required this.albums,
    required this.tracks,
    required this.onPlay,
  });

  final List<AlbumSummary> albums;
  final List<Track> tracks;
  final ValueChanged<Track> onPlay;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const _EmptyState(message: 'No album folders detected');
    }

    final tracksByFolder = _tracksByFolder(tracks);
    return ListView.builder(
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final firstTrack = tracksByFolder[album.folderPath]?.firstOrNull;
        return ListTile(
          leading: const Icon(Icons.album),
          title: Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${album.albumArtist}${album.year == null ? '' : ' · ${album.year}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text('${album.trackCount} tracks'),
          onTap: firstTrack == null ? null : () => onPlay(firstTrack),
        );
      },
    );
  }
}

class _FolderList extends StatelessWidget {
  const _FolderList({
    required this.folders,
    required this.tracks,
    required this.onPlay,
  });

  final List<FolderSummary> folders;
  final List<Track> tracks;
  final ValueChanged<Track> onPlay;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return const _EmptyState(message: 'No playlist folders detected');
    }

    final tracksByFolder = _tracksByFolder(tracks);
    return ListView.builder(
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        final firstTrack = tracksByFolder[folder.path]?.firstOrNull;
        return ListTile(
          leading: const Icon(Icons.queue_music),
          title: Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${folder.albumCount} albums · ${folder.artistCount} artists · confidence ${(folder.confidence * 100).round()}%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text('${folder.trackCount} tracks'),
          onTap: firstTrack == null ? null : () => onPlay(firstTrack),
        );
      },
    );
  }
}

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({
    required this.track,
    required this.playing,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
  });

  final Track? track;
  final bool playing;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
          color: scheme.surface,
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            const Icon(Icons.music_note),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track?.title ?? 'Nothing playing',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    track == null
                        ? 'Select a local track'
                        : '${track!.artist} · ${track!.folderName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
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
      ),
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

Map<String, List<Track>> _tracksByFolder(List<Track> tracks) {
  final grouped = <String, List<Track>>{};
  for (final track in tracks) {
    grouped.putIfAbsent(track.folderPath, () => []).add(track);
  }
  return grouped;
}

String _formatDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) {
    return '-';
  }
  final totalSeconds = durationMs ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
