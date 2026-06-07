import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'album_playback_view.dart';
import 'album_views.dart';
import 'artwork_resolver.dart';
import 'library_controller.dart';
import 'library_diff.dart';
import 'library_sidebar.dart';
import 'library_types.dart';
import 'models.dart';
import 'playback_controller.dart';
import 'playlist_views.dart';
import 'rescan_dialog.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _library = LibraryController();
  final _playback = PlaybackController();
  final _playlistListScrollController = ScrollController();

  _ActiveAlbumPlayback? _activeAlbumPlayback;
  _ActivePlaylistPlayback? _activePlaylistPlayback;
  String? _lastPlaybackPath;
  bool _lastPlaybackPlaying = false;
  LibraryView _view = LibraryView.albums;
  String? _selectedPlaylistPath;
  double _playlistListScrollOffset = 0;
  bool _rescanDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _library.addListener(_handleLibraryChanged);
    _playback.addListener(_handlePlaybackChanged);
    unawaited(_library.open());
  }

  @override
  void dispose() {
    _playlistListScrollController.dispose();
    _library
      ..removeListener(_handleLibraryChanged)
      ..dispose();
    _playback
      ..removeListener(_handlePlaybackChanged)
      ..dispose();
    super.dispose();
  }

  void _handleLibraryChanged() {
    if (!mounted) {
      return;
    }
    setState(_syncActiveSelectionsWithLibrary);
  }

  void _syncActiveSelectionsWithLibrary() {
    final folders = _library.folders;
    final albums = _library.albums;
    final tracks = _library.tracks;
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
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    }

    final activePlaylist = _activePlaylistPlayback;
    if (activePlaylist != null &&
        (!folders.any((folder) => folder.path == activePlaylist.folderPath) ||
            activePlaylist.tracks.any(
              (track) => !currentTrackPaths.contains(track.path),
            ))) {
      _activePlaylistPlayback = null;
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    }
  }

  void _handlePlaybackChanged() {
    final activeAlbumPlayback = _activeAlbumPlayback;
    final activePlaylistPlayback = _activePlaylistPlayback;
    if (!mounted) {
      return;
    }
    final displayTrack = activeAlbumPlayback == null
        ? activePlaylistPlayback == null
              ? _playback.currentTrack
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

  void _handleRescanPressed() {
    _openRescanModal();
    _library.startRescanDiff();
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
          stateListenable: _library.rescanState,
          trackCoverCacheListenable: _library.trackCoverCacheListenable,
          onApply: _applyPendingDiff,
          onRescan: () => _library.startRescanDiff(),
          onFullRescan: () => _library.startRescanDiff(full: true),
        );
      },
    ).whenComplete(() => _rescanDialogOpen = false);
  }

  Future<void> _applyPendingDiff() async {
    final diff = await _library.applyPendingDiff(
      confirmLargeDeletion: _confirmLargeDeletion,
    );
    if (mounted && diff != null) {
      await _playback.stopIfCurrentRemoved(
        diff.removed.map((change) => change.path),
      );
    }
  }

  Future<void> _handleMusicRootPressed() async {
    if (!_library.canChangeMusicRoot) {
      return;
    }

    final nextRoot = await _showMusicRootDialog();
    if (!mounted || nextRoot == null || nextRoot == _library.musicRoot) {
      return;
    }
    final changed = await _library.changeMusicRoot(nextRoot);
    if (mounted && changed) {
      setState(() {
        _selectedPlaylistPath = null;
      });
    }
  }

  Future<String?> _showMusicRootDialog() async {
    final controller = TextEditingController(text: _library.musicRoot);
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

  Future<void> _playAlbumFrom(
    AlbumSummary album,
    List<Track> tracks,
    Track track,
  ) async {
    if (tracks.isEmpty) {
      return;
    }
    setState(() {
      _activeAlbumPlayback = _ActiveAlbumPlayback(album: album, tracks: tracks);
      _activePlaylistPlayback = null;
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _playQueueFrom(tracks, track);
  }

  Future<void> _playAlbum(AlbumSummary album, List<Track> tracks) async {
    if (tracks.isEmpty) {
      return;
    }
    await _playAlbumFrom(album, tracks, tracks.first);
  }

  void _openAlbumPlayback(AlbumSummary album, List<Track> tracks) {
    if (tracks.isEmpty) {
      return;
    }
    setState(() {
      _activeAlbumPlayback = _ActiveAlbumPlayback(album: album, tracks: tracks);
      final currentAlbumTrack = _currentTrackForAlbum(_activeAlbumPlayback!);
      final showingCurrentAlbum = _playback.isCurrentQueue(tracks);
      _lastPlaybackPath = showingCurrentAlbum ? currentAlbumTrack?.path : null;
      _lastPlaybackPlaying =
          showingCurrentAlbum && currentAlbumTrack != null && _playback.playing;
    });
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

  List<FolderSummary> get _playlistFolders => _library.playlistFolders;

  int get _playlistCount => _library.playlistCount;

  Map<String, List<Track>> get _tracksByFolder => _library.tracksByFolder;

  _NowPlayingTarget? get _nowPlayingTarget {
    final currentTrack = _playback.currentTrack;
    if (currentTrack == null) {
      return null;
    }

    final activePlaylist = _activePlaylistPlayback;
    if (activePlaylist != null &&
        _currentTrackForPlaylist(activePlaylist) != null) {
      final folder = _playlistFolderForPath(activePlaylist.folderPath);
      if (folder != null) {
        return _NowPlayingTarget.playlist(
          folder: folder,
          tracks: activePlaylist.tracks,
          sidebarItem: SidebarNowPlaying.playlist(
            playlistCoverArtPaths: _playlistCoverArtPaths(
              folder,
              activePlaylist.tracks,
            ),
            playing: _playback.playing,
          ),
        );
      }
    }

    final activeAlbum = _activeAlbumPlayback;
    if (activeAlbum != null &&
        _playback.isCurrentQueue(activeAlbum.tracks) &&
        _currentTrackForAlbum(activeAlbum) != null) {
      return _NowPlayingTarget.album(
        album: activeAlbum.album,
        tracks: activeAlbum.tracks,
        sidebarItem: SidebarNowPlaying.album(
          coverArtPath: activeAlbum.album.coverArtPath,
          playing: _playback.playing,
        ),
      );
    }

    final album = _albumForCurrentTrack(currentTrack);
    if (album == null) {
      return null;
    }
    final tracks = _tracksByFolder[album.folderPath] ?? const <Track>[];
    if (!_playback.isCurrentQueue(tracks)) {
      return null;
    }
    return _NowPlayingTarget.album(
      album: album,
      tracks: tracks,
      sidebarItem: SidebarNowPlaying.album(
        coverArtPath: album.coverArtPath,
        playing: _playback.playing,
      ),
    );
  }

  AlbumSummary? _albumForCurrentTrack(Track currentTrack) {
    return _library.albums
        .where((album) => album.folderPath == currentTrack.folderPath)
        .firstOrNull;
  }

  FolderSummary? _playlistFolderForPath(String path) {
    return _library.folders
        .where(
          (folder) => folder.kind == FolderKind.playlist && folder.path == path,
        )
        .firstOrNull;
  }

  List<String?> _playlistCoverArtPaths(
    FolderSummary folder,
    List<Track> tracks,
  ) {
    final paths = tracks
        .take(4)
        .map((track) => resolveTrackArtwork(track, _library.trackCoverCache))
        .toList(growable: true);
    if (paths.every((path) => path == null || path.isEmpty)) {
      paths
        ..clear()
        ..add(folder.coverArtPath);
    }
    return paths;
  }

  void _openNowPlaying(_NowPlayingTarget target) {
    switch (target.kind) {
      case _NowPlayingKind.album:
        final album = target.album;
        final tracks = target.tracks;
        if (album == null || tracks.isEmpty) {
          return;
        }
        setState(() {
          _activeAlbumPlayback = _ActiveAlbumPlayback(
            album: album,
            tracks: tracks,
          );
          _activePlaylistPlayback = null;
          _lastPlaybackPath = _playback.currentTrack?.path;
          _lastPlaybackPlaying = _playback.playing;
        });
      case _NowPlayingKind.playlist:
        final folder = target.folder;
        if (folder == null) {
          return;
        }
        setState(() {
          _view = LibraryView.playlists;
          _selectedPlaylistPath = folder.path;
          _activeAlbumPlayback = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeAlbumPlayback = _activeAlbumPlayback;
    final albumPlaybackActive =
        activeAlbumPlayback != null &&
        _playback.isCurrentQueue(activeAlbumPlayback.tracks);
    final activeAlbumTrack = albumPlaybackActive
        ? _currentTrackForAlbum(activeAlbumPlayback)
        : null;
    final nowPlayingTarget = _nowPlayingTarget;
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              LibrarySidebar(
                selected: _view,
                albums: _library.albums.length,
                playlists: _playlistCount,
                scanState: _library.scanState,
                musicRoot: _library.musicRoot,
                scanning: _library.scanning,
                progress: _library.scanProgress,
                error: _library.error,
                nowPlaying: nowPlayingTarget?.sidebarItem,
                onEditMusicRoot: _handleMusicRootPressed,
                onRescan: _handleRescanPressed,
                onOpenNowPlaying: nowPlayingTarget == null
                    ? null
                    : () => _openNowPlaying(nowPlayingTarget),
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
                  albumPlaybackActive
                      ? _playback.togglePlayPause(activeAlbumPlayback.tracks)
                      : _playAlbum(
                          activeAlbumPlayback.album,
                          activeAlbumPlayback.tracks,
                        ),
                ),
                onNext: () =>
                    unawaited(_playback.skip(1, activeAlbumPlayback.tracks)),
                onPlayTrack: (track) => unawaited(
                  _playAlbumFrom(
                    activeAlbumPlayback.album,
                    activeAlbumPlayback.tracks,
                    track,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_library.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return switch (_view) {
      LibraryView.albums => AlbumGrid(
        albums: _library.albums,
        tracksByFolder: _tracksByFolder,
        onOpen: _openAlbumPlayback,
      ),
      LibraryView.playlists => _buildPlaylistsContent(),
    };
  }

  Widget _buildPlaylistsContent() {
    final selectedPath = _selectedPlaylistPath;
    final selectedFolder = selectedPath == null
        ? null
        : _library.folders
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
        trackCoverCache: _library.trackCoverCache,
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
      trackCoverCache: _library.trackCoverCache,
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

enum _NowPlayingKind { album, playlist }

class _NowPlayingTarget {
  const _NowPlayingTarget.album({
    required AlbumSummary this.album,
    required this.tracks,
    required this.sidebarItem,
  }) : kind = _NowPlayingKind.album,
       folder = null;

  const _NowPlayingTarget.playlist({
    required FolderSummary this.folder,
    required this.tracks,
    required this.sidebarItem,
  }) : kind = _NowPlayingKind.playlist,
       album = null;

  final _NowPlayingKind kind;
  final AlbumSummary? album;
  final FolderSummary? folder;
  final List<Track> tracks;
  final SidebarNowPlaying sidebarItem;
}
