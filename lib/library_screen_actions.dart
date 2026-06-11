part of 'library_screen.dart';

extension _LibraryScreenActions on _LibraryScreenState {
  void _handleLibraryChanged() {
    if (!mounted) {
      return;
    }
    _mutate(_syncActiveSelectionsWithLibrary);
    _syncThemeModeWithLibrary();
    _applyAudioOutputSettingsIfReady();
    unawaited(_restoreLastPlaybackIfReady());
  }

  void _syncThemeModeWithLibrary() {
    if (!_library.settingsLoaded) {
      return;
    }
    final loadedMode = themeModeFromDb(_library.themeMode);
    if (loadedMode != widget.themeMode) {
      widget.onThemeModeChanged(loadedMode);
    }
  }

  void _handleToggleThemeMode() {
    if (!_library.settingsLoaded) {
      return;
    }
    final nextMode = widget.themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    widget.onThemeModeChanged(nextMode);
    unawaited(
      _library.saveThemeMode(themeModeToDb(nextMode)).catchError((_) {}),
    );
  }

  void _applyAudioOutputSettingsIfReady() {
    if (_audioOutputSettingsApplied || !_library.settingsLoaded) {
      return;
    }
    _audioOutputSettingsApplied = true;
    unawaited(
      _playback
          .applyAudioOutputSettings(_library.audioOutputSettings)
          .catchError((_) {}),
    );
  }

  void _syncActiveSelectionsWithLibrary() {
    final folders = _library.folders;
    final albums = _library.albums;
    final tracks = _library.tracks;
    final activePlaylistOverlayPath = _activePlaylistOverlayPath;
    if (activePlaylistOverlayPath != null &&
        playlistFolderForPath(activePlaylistOverlayPath, folders) == null) {
      _activePlaylistOverlayPath = null;
    }

    final currentTrackPaths = tracks.map((track) => track.path).toSet();
    final activeAlbum = _activeAlbumPlayback;
    if (activeAlbum != null &&
        !activeAlbumStillAvailable(
          activeAlbum: activeAlbum,
          albums: albums,
          currentTrackPaths: currentTrackPaths,
        )) {
      _activeAlbumPlayback = null;
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    }

    final activePlaylist = _activePlaylistPlayback;
    if (activePlaylist != null &&
        !activePlaylistStillAvailable(
          activePlaylist: activePlaylist,
          folders: folders,
          currentTrackPaths: currentTrackPaths,
        )) {
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
    _mutate(() {
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
    final track = trackByPathOrFirst(tracks, state.trackPath);
    _mutate(() {
      _activeAlbumPlayback = LibraryActiveAlbumPlayback(
        album: album,
        tracks: tracks,
      );
      _activePlaylistPlayback = null;
      _activePlaylistOverlayPath = null;
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _restoreQueueFrom(tracks, track, play: state.playing);
  }

  Future<void> _restorePlaylistPlayback(LastPlaybackState state) async {
    final folder = playlistFolderForPath(state.folderPath, _library.folders);
    if (folder == null) {
      return;
    }
    final tracks = _tracksByFolder[folder.path] ?? const <Track>[];
    if (tracks.isEmpty || !mounted) {
      return;
    }
    final queue = state.shuffled ? shuffledTracks(tracks) : tracks;
    final track = trackByPathOrFirst(queue, state.trackPath);
    _mutate(() {
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = LibraryActivePlaylistPlayback(
        folderPath: folder.path,
        tracks: tracks,
        shuffled: state.shuffled,
      );
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _restoreQueueFrom(queue, track, play: state.playing);
  }

  void _saveCurrentPlaybackStateIfChanged() {
    final state = currentPlaybackState(
      currentTrack: _playback.currentTrack,
      playing: _playback.playing,
      activePlaylist: _activePlaylistPlayback,
      activeAlbum: _activeAlbumPlayback,
      albums: _library.albums,
      tracksByFolder: _tracksByFolder,
      isCurrentQueue: _playback.isCurrentQueue,
    );
    if (state == null) {
      return;
    }
    final key = lastPlaybackStateKey(state);
    if (key == _lastPersistedPlaybackKey) {
      return;
    }
    _lastPersistedPlaybackKey = key;
    unawaited(_library.saveLastPlayback(state));
  }

  void _openRescanModal() {
    if (_rescanDialogOpen) {
      return;
    }
    _library.prepareRescanDialog();
    _rescanDialogOpen = true;
    showLibraryRescanDialog(
      context: context,
      library: _library,
      onEditMusicRoot: _handleMusicRootPressed,
      onApply: _applyPendingDiff,
    ).whenComplete(() => _rescanDialogOpen = false);
  }

  Future<bool> _applyPendingDiff() async {
    final diff = await _library.applyPendingDiff(
      confirmLargeDeletion: (risk) =>
          showLargeDeletionConfirmation(context, risk),
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

    final nextRoot = await showMusicRootDialog(
      context,
      musicRoot: _library.musicRoot,
    );
    if (!mounted || nextRoot == null || nextRoot == _library.musicRoot) {
      return;
    }
    final previousTrackPaths = _library.tracks
        .map((track) => track.path)
        .toSet();
    final changed = await _library.changeMusicRoot(nextRoot);
    if (mounted && changed) {
      final currentTrackPaths = _library.tracks
          .map((track) => track.path)
          .toSet();
      await _playback.stopIfCurrentRemoved(
        previousTrackPaths.difference(currentTrackPaths),
      );
      _mutate(() {
        _activePlaylistOverlayPath = null;
      });
    }
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
    _mutate(() {
      _activeAlbumPlayback = LibraryActiveAlbumPlayback(
        album: album,
        tracks: tracks,
      );
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
    _mutate(() {
      _activeAlbumPlayback = LibraryActiveAlbumPlayback(
        album: album,
        tracks: tracks,
      );
      _activePlaylistOverlayPath = null;
      final currentAlbumTrack = _currentTrackForAlbum(_activeAlbumPlayback!);
      final showingCurrentAlbum = _playback.isCurrentQueue(tracks);
      _lastPlaybackPath = showingCurrentAlbum ? currentAlbumTrack?.path : null;
      _lastPlaybackPlaying =
          showingCurrentAlbum && currentAlbumTrack != null && _playback.playing;
    });
  }

  LibraryAlbumPlaybackSwitchTarget? _albumPlaybackSwitchTarget(
    AlbumSummary album,
    int delta,
  ) {
    return albumPlaybackSwitchTarget(
      album: album,
      delta: delta,
      albums: _library.albums,
      tracksByFolder: _tracksByFolder,
    );
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
    _mutate(() {
      _activeAlbumPlayback = LibraryActiveAlbumPlayback(
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
    _mutate(() {
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = LibraryActivePlaylistPlayback(
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
    final shuffled = shuffledTracks(tracks);
    _mutate(() {
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = LibraryActivePlaylistPlayback(
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

  LibraryNowPlayingTarget? get _nowPlayingTarget {
    return nowPlayingTarget(
      currentTrack: _playback.currentTrack,
      playing: _playback.playing,
      activePlaylist: _activePlaylistPlayback,
      activeAlbum: _activeAlbumPlayback,
      albums: _library.albums,
      folders: _library.folders,
      tracksByFolder: _tracksByFolder,
      trackCoverCache: _library.trackCoverCache,
      isCurrentQueue: _playback.isCurrentQueue,
    );
  }

  void _openNowPlaying(LibraryNowPlayingTarget target) {
    switch (target.kind) {
      case LibraryNowPlayingKind.album:
        final album = target.album;
        final tracks = target.tracks;
        if (album == null || tracks.isEmpty) {
          return;
        }
        _saveAlbumGridScrollOffset();
        _mutate(() {
          _activeAlbumPlayback = LibraryActiveAlbumPlayback(
            album: album,
            tracks: tracks,
          );
          _activePlaylistPlayback = null;
          _activePlaylistOverlayPath = null;
          _lastPlaybackPath = _playback.currentTrack?.path;
          _lastPlaybackPlaying = _playback.playing;
        });
      case LibraryNowPlayingKind.playlist:
        final folder = target.folder;
        if (folder == null) {
          return;
        }
        _openPlaylistPlayback(folder);
    }
  }

  FolderSummary? get _activePlaylistOverlayFolder {
    final path = _activePlaylistOverlayPath;
    if (path == null) {
      return null;
    }
    return playlistFolderForPath(path, _library.folders);
  }

  void _openPlaylistPlayback(FolderSummary folder) {
    if (_view == LibraryView.playlists) {
      _savePlaylistListScrollOffset();
    }
    _mutate(() {
      _activePlaylistOverlayPath = folder.path;
      _activeAlbumPlayback = null;
    });
  }

  void _selectLibraryView(LibraryView view) {
    final currentView = _view;
    if (currentView == view) {
      return;
    }

    if (currentView == LibraryView.albums && view != LibraryView.albums) {
      _saveAlbumGridScrollOffset();
    }
    if (currentView == LibraryView.playlists &&
        view != LibraryView.playlists &&
        _activePlaylistOverlayPath == null) {
      _savePlaylistListScrollOffset();
    }
    _mutate(() => _view = view);
    if (currentView != LibraryView.albums && view == LibraryView.albums) {
      _restoreAlbumGridScrollOffset();
    }
    if (view == LibraryView.playlists && _activePlaylistOverlayPath == null) {
      _restorePlaylistListScrollOffset();
    }
  }

  void _openSettingsModal() {
    if (!_library.settingsLoaded) {
      return;
    }
    unawaited(
      showLibrarySettingsDialog(
        context: context,
        library: _library,
        playback: _playback,
      ),
    );
  }

  void _closeAlbumPlayback() {
    _mutate(() => _activeAlbumPlayback = null);
    _restoreAlbumGridScrollOffset();
  }

  void _closePlaylistPlayback() {
    _mutate(() => _activePlaylistOverlayPath = null);
    _restorePlaylistListScrollOffset();
  }

  Track? _currentTrackForAlbum(LibraryActiveAlbumPlayback albumPlayback) {
    return currentTrackForAlbum(
      albumPlayback: albumPlayback,
      currentTrack: _playback.currentTrack,
    );
  }

  Track? _currentTrackForPlaylist(
    LibraryActivePlaylistPlayback playlistPlayback,
  ) {
    return currentTrackForPlaylist(
      playlistPlayback: playlistPlayback,
      currentTrack: _playback.currentTrack,
    );
  }

  void _saveAlbumGridScrollOffset() {
    _scrollMemory.saveAlbumGridScrollOffset();
  }

  void _restoreAlbumGridScrollOffset() {
    _scrollMemory.restoreAlbumGridScrollOffset(
      isMounted: () => mounted,
      currentView: () => _view,
    );
  }

  void _savePlaylistListScrollOffset() {
    _scrollMemory.savePlaylistListScrollOffset();
  }

  void _restorePlaylistListScrollOffset() {
    _scrollMemory.restorePlaylistListScrollOffset(
      isMounted: () => mounted,
      currentView: () => _view,
      hasPlaylistOverlay: () => _activePlaylistOverlayPath != null,
    );
  }
}
