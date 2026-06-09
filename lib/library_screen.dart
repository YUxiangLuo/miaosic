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
  final _albumGridScrollController = ScrollController();
  final _playlistListScrollController = ScrollController();

  _ActiveAlbumPlayback? _activeAlbumPlayback;
  _ActivePlaylistPlayback? _activePlaylistPlayback;
  String? _lastPlaybackPath;
  String? _lastNowPlayingPath;
  String? _lastPersistedPlaybackKey;
  bool _lastPlaybackPlaying = false;
  bool _lastNowPlayingPlaying = false;
  bool _lastPlaybackRestoreAttempted = false;
  bool _lastPlaybackRestoring = false;
  LibraryView _view = LibraryView.albums;
  String? _selectedPlaylistPath;
  double _albumGridScrollOffset = 0;
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
    _albumGridScrollController.dispose();
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
    unawaited(_restoreLastPlaybackIfReady());
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
    _saveCurrentPlaybackStateIfChanged();
    final displayTrack = activeAlbumPlayback == null
        ? activePlaylistPlayback == null
              ? _playback.currentTrack
              : _currentTrackForPlaylist(activePlaylistPlayback)
        : _currentTrackForAlbum(activeAlbumPlayback);
    final nextPath = displayTrack?.path;
    final nextPlaying = nextPath != null && _playback.playing;
    final nextNowPlayingPath = _playback.currentTrack?.path;
    final nextNowPlayingPlaying =
        nextNowPlayingPath != null && _playback.playing;
    if (nextPath == _lastPlaybackPath &&
        nextPlaying == _lastPlaybackPlaying &&
        nextNowPlayingPath == _lastNowPlayingPath &&
        nextNowPlayingPlaying == _lastNowPlayingPlaying) {
      return;
    }
    setState(() {
      _lastPlaybackPath = nextPath;
      _lastPlaybackPlaying = nextPlaying;
      _lastNowPlayingPath = nextNowPlayingPath;
      _lastNowPlayingPlaying = nextNowPlayingPlaying;
    });
  }

  Future<void> _restoreLastPlaybackIfReady() async {
    if (_lastPlaybackRestoreAttempted ||
        _lastPlaybackRestoring ||
        !_library.canRestoreLastPlayback ||
        _library.tracks.isEmpty) {
      return;
    }

    final state = _library.lastPlayback;
    if (state == null) {
      _lastPlaybackRestoreAttempted = true;
      return;
    }

    _lastPlaybackRestoreAttempted = true;
    _lastPlaybackRestoring = true;
    try {
      switch (state.kind) {
        case LastPlaybackKind.album:
          await _restoreAlbumPlayback(state);
        case LastPlaybackKind.playlist:
          await _restorePlaylistPlayback(state);
      }
    } finally {
      _lastPlaybackRestoring = false;
    }
  }

  Future<void> _restoreAlbumPlayback(LastPlaybackState state) async {
    final album = _library.albums
        .where((album) => album.folderPath == state.folderPath)
        .firstOrNull;
    if (album == null) {
      return;
    }
    final tracks = _tracksByFolder[album.folderPath] ?? const <Track>[];
    if (tracks.isEmpty || !mounted) {
      return;
    }
    final track = _trackByPathOrFirst(tracks, state.trackPath);
    setState(() {
      _activeAlbumPlayback = _ActiveAlbumPlayback(album: album, tracks: tracks);
      _activePlaylistPlayback = null;
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _restoreQueueFrom(tracks, track, play: state.playing);
  }

  Future<void> _restorePlaylistPlayback(LastPlaybackState state) async {
    final folder = _playlistFolderForPath(state.folderPath);
    if (folder == null) {
      return;
    }
    final tracks = _tracksByFolder[folder.path] ?? const <Track>[];
    if (tracks.isEmpty || !mounted) {
      return;
    }
    final queue = state.shuffled ? _shuffledTracks(tracks) : tracks;
    final track = _trackByPathOrFirst(queue, state.trackPath);
    setState(() {
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = _ActivePlaylistPlayback(
        folderPath: folder.path,
        tracks: tracks,
        shuffled: state.shuffled,
      );
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _restoreQueueFrom(queue, track, play: state.playing);
  }

  List<Track> _shuffledTracks(List<Track> tracks) {
    return tracks.toList(growable: false)..shuffle(math.Random());
  }

  Track _trackByPathOrFirst(List<Track> tracks, String path) {
    return tracks.firstWhere(
      (track) => track.path == path,
      orElse: () => tracks.first,
    );
  }

  void _saveCurrentPlaybackStateIfChanged() {
    final state = _currentPlaybackState();
    if (state == null) {
      return;
    }
    final key = _lastPlaybackStateKey(state);
    if (key == _lastPersistedPlaybackKey) {
      return;
    }
    _lastPersistedPlaybackKey = key;
    unawaited(_library.saveLastPlayback(state));
  }

  LastPlaybackState? _currentPlaybackState() {
    final currentTrack = _playback.currentTrack;
    if (currentTrack == null) {
      return null;
    }

    final activePlaylist = _activePlaylistPlayback;
    if (activePlaylist != null &&
        _currentTrackForPlaylist(activePlaylist) != null) {
      return LastPlaybackState(
        kind: LastPlaybackKind.playlist,
        folderPath: activePlaylist.folderPath,
        trackPath: currentTrack.path,
        playing: _playback.playing,
        shuffled: activePlaylist.shuffled,
      );
    }

    final activeAlbum = _activeAlbumPlayback;
    if (activeAlbum != null &&
        _playback.isCurrentQueue(activeAlbum.tracks) &&
        _currentTrackForAlbum(activeAlbum) != null) {
      return LastPlaybackState(
        kind: LastPlaybackKind.album,
        folderPath: activeAlbum.album.folderPath,
        trackPath: currentTrack.path,
        playing: _playback.playing,
        shuffled: false,
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
    return LastPlaybackState(
      kind: LastPlaybackKind.album,
      folderPath: album.folderPath,
      trackPath: currentTrack.path,
      playing: _playback.playing,
      shuffled: false,
    );
  }

  String _lastPlaybackStateKey(LastPlaybackState state) {
    return '${state.kind.dbValue}\n${state.folderPath}\n${state.trackPath}\n${state.playing}\n${state.shuffled}';
  }

  void _openRescanModal() {
    if (_rescanDialogOpen) {
      return;
    }
    _rescanDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return RescanDialog(
          stateListenable: _library.rescanState,
          trackCoverCacheListenable: _library.trackCoverCacheListenable,
          musicRoot: _library.musicRoot,
          canEditMusicRoot: _library.canChangeMusicRoot,
          onEditMusicRoot: _handleMusicRootPressed,
          onApply: _applyPendingDiff,
          onRescan: () => _library.startRescanDiff(),
          onFullRescan: () => _library.startRescanDiff(full: true),
        );
      },
    ).whenComplete(() => _rescanDialogOpen = false);
  }

  Future<bool> _applyPendingDiff() async {
    final diff = await _library.applyPendingDiff(
      confirmLargeDeletion: _confirmLargeDeletion,
    );
    if (mounted && diff != null) {
      await _playback.stopIfCurrentRemoved(
        diff.removed.map((change) => change.path),
      );
    }
    return diff != null;
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

  Future<void> _restoreQueueFrom(
    List<Track> queue,
    Track track, {
    required bool play,
  }) {
    return _playback.restoreQueueFrom(queue, track, play: play);
  }

  Future<void> _playAlbumFrom(
    AlbumSummary album,
    List<Track> tracks,
    Track track,
  ) async {
    if (tracks.isEmpty) {
      return;
    }
    _saveAlbumGridScrollOffset();
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
    _saveAlbumGridScrollOffset();
    setState(() {
      _activeAlbumPlayback = _ActiveAlbumPlayback(album: album, tracks: tracks);
      final currentAlbumTrack = _currentTrackForAlbum(_activeAlbumPlayback!);
      final showingCurrentAlbum = _playback.isCurrentQueue(tracks);
      _lastPlaybackPath = showingCurrentAlbum ? currentAlbumTrack?.path : null;
      _lastPlaybackPlaying =
          showingCurrentAlbum && currentAlbumTrack != null && _playback.playing;
    });
  }

  _AlbumPlaybackSwitchTarget? _albumPlaybackSwitchTarget(
    AlbumSummary album,
    int delta,
  ) {
    final albums = _library.albums;
    if (albums.length < 2 || delta == 0) {
      return null;
    }
    final currentIndex = albums.indexWhere(
      (candidate) => candidate.folderPath == album.folderPath,
    );
    if (currentIndex < 0) {
      return null;
    }

    final step = delta.sign;
    for (var offset = 1; offset < albums.length; offset += 1) {
      final index = (currentIndex + step * offset) % albums.length;
      final nextAlbum = albums[index];
      final nextTracks =
          _tracksByFolder[nextAlbum.folderPath] ?? const <Track>[];
      if (nextTracks.isNotEmpty) {
        return _AlbumPlaybackSwitchTarget(album: nextAlbum, tracks: nextTracks);
      }
    }
    return null;
  }

  void _switchAlbumPlayback(int delta) {
    final activeAlbumPlayback = _activeAlbumPlayback;
    if (activeAlbumPlayback == null) {
      return;
    }
    final target = _albumPlaybackSwitchTarget(activeAlbumPlayback.album, delta);
    if (target == null) {
      return;
    }
    setState(() {
      _activeAlbumPlayback = _ActiveAlbumPlayback(
        album: target.album,
        tracks: target.tracks,
      );
      final currentAlbumTrack = _currentTrackForAlbum(_activeAlbumPlayback!);
      final showingCurrentAlbum = _playback.isCurrentQueue(target.tracks);
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
        shuffled: false,
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
    final shuffled = _shuffledTracks(tracks);
    setState(() {
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = _ActivePlaylistPlayback(
        folderPath: folder.path,
        tracks: tracks,
        shuffled: true,
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
        _saveAlbumGridScrollOffset();
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
        if (_view == LibraryView.playlists && _selectedPlaylistPath == null) {
          _savePlaylistListScrollOffset();
        }
        _saveAlbumGridScrollOffset();
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
    final _NowPlayingTarget? dockNowPlayingAlbumTarget;
    if (activeAlbumPlayback != null &&
        nowPlayingTarget != null &&
        nowPlayingTarget.kind == _NowPlayingKind.album &&
        nowPlayingTarget.album?.folderPath !=
            activeAlbumPlayback.album.folderPath) {
      dockNowPlayingAlbumTarget = nowPlayingTarget;
    } else {
      dockNowPlayingAlbumTarget = null;
    }
    return Scaffold(
      body: Stack(
        children: [
          ExcludeFocus(
            excluding: activeAlbumPlayback != null,
            child: Row(
              children: [
                LibrarySidebar(
                  selected: _view,
                  albums: _library.albums.length,
                  playlists: _playlistCount,
                  nowPlaying: nowPlayingTarget?.sidebarItem,
                  onOpenLibrary: _openRescanModal,
                  onOpenNowPlaying: nowPlayingTarget == null
                      ? null
                      : () => _openNowPlaying(nowPlayingTarget),
                  onSelected: _selectLibraryView,
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
          if (activeAlbumPlayback != null)
            Positioned.fill(
              child: AlbumPlaybackView(
                album: activeAlbumPlayback.album,
                tracks: activeAlbumPlayback.tracks,
                currentTrack: activeAlbumTrack,
                playing: activeAlbumTrack != null && _playback.playing,
                nowPlayingAlbum: dockNowPlayingAlbumTarget == null
                    ? null
                    : AlbumPlaybackNowPlaying(
                        coverArtPath:
                            dockNowPlayingAlbumTarget.album?.coverArtPath,
                        playing: dockNowPlayingAlbumTarget.sidebarItem.playing,
                      ),
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
                onOpenNowPlayingAlbum: dockNowPlayingAlbumTarget == null
                    ? null
                    : () => _openNowPlaying(dockNowPlayingAlbumTarget!),
                canSwitchPreviousAlbum:
                    _albumPlaybackSwitchTarget(activeAlbumPlayback.album, -1) !=
                    null,
                canSwitchNextAlbum:
                    _albumPlaybackSwitchTarget(activeAlbumPlayback.album, 1) !=
                    null,
                onSwitchPreviousAlbum: () => _switchAlbumPlayback(-1),
                onSwitchNextAlbum: () => _switchAlbumPlayback(1),
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
        scrollController: _albumGridScrollController,
        keyboardShortcutsEnabled: _activeAlbumPlayback == null,
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

  void _selectLibraryView(LibraryView view) {
    final currentView = _view;
    final showingPlaylistList =
        currentView == LibraryView.playlists && _selectedPlaylistPath == null;
    if (currentView == view &&
        (currentView == LibraryView.albums || showingPlaylistList)) {
      return;
    }

    if (currentView == LibraryView.albums && view != LibraryView.albums) {
      _saveAlbumGridScrollOffset();
    }
    if (currentView == LibraryView.playlists &&
        view != LibraryView.playlists &&
        _selectedPlaylistPath == null) {
      _savePlaylistListScrollOffset();
    }
    setState(() {
      _view = view;
      _selectedPlaylistPath = null;
    });
    if (currentView != LibraryView.albums && view == LibraryView.albums) {
      _restoreAlbumGridScrollOffset();
    }
    if (!showingPlaylistList && view == LibraryView.playlists) {
      _restorePlaylistListScrollOffset();
    }
  }

  void _closeAlbumPlayback() {
    setState(() => _activeAlbumPlayback = null);
    _restoreAlbumGridScrollOffset();
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

  void _saveAlbumGridScrollOffset() {
    if (_albumGridScrollController.hasClients) {
      _albumGridScrollOffset = _albumGridScrollController.offset;
    }
  }

  void _restoreAlbumGridScrollOffset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _view != LibraryView.albums ||
          !_albumGridScrollController.hasClients) {
        return;
      }
      final position = _albumGridScrollController.position;
      final target = _albumGridScrollOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _albumGridScrollController.jumpTo(target);
    });
  }

  void _savePlaylistListScrollOffset() {
    if (_playlistListScrollController.hasClients) {
      _playlistListScrollOffset = _playlistListScrollController.offset;
    }
  }

  void _restorePlaylistListScrollOffset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _view != LibraryView.playlists ||
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

class _AlbumPlaybackSwitchTarget {
  const _AlbumPlaybackSwitchTarget({required this.album, required this.tracks});

  final AlbumSummary album;
  final List<Track> tracks;
}

class _ActivePlaylistPlayback {
  const _ActivePlaylistPlayback({
    required this.folderPath,
    required this.tracks,
    required this.shuffled,
  });

  final String folderPath;
  final List<Track> tracks;
  final bool shuffled;
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
