part of 'library_screen.dart';

extension _LibraryScreenActions on _LibraryScreenState {
  void _handleLibraryChanged() {
    if (!mounted) {
      return;
    }
    _mutate(_syncActiveSelectionsWithLibrary);
    _syncThemeModeWithLibrary();
    _applyAudioOutputSettingsIfReady();
    _showBackgroundWarningIfNeeded();
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
    final previousMode = widget.themeMode;
    final nextMode = previousMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    widget.onThemeModeChanged(nextMode);
    unawaited(_persistThemeMode(previousMode, nextMode));
  }

  Future<void> _persistThemeMode(
    ThemeMode previousMode,
    ThemeMode nextMode,
  ) async {
    try {
      await _library.saveThemeMode(themeModeToDb(nextMode));
    } catch (error) {
      if (!mounted) {
        return;
      }
      widget.onThemeModeChanged(previousMode);
      _showTransientMessage('Could not save theme: $error');
    }
  }

  void _applyAudioOutputSettingsIfReady() {
    if (_audioOutputSettingsApplied || !_library.settingsLoaded) {
      return;
    }
    _audioOutputSettingsApplied = true;
    unawaited(
      _playback
          .applyAudioOutputSettings(_library.audioOutputSettings)
          .catchError((Object error) {
            if (!mounted) {
              return;
            }
            _showTransientMessage('Could not apply audio output: $error');
          }),
    );
  }

  void _showAlbumOverlay(AlbumSummary album, List<Track> tracks) {
    _overlay = LibraryPlaybackOverlay.album(album: album, tracks: tracks);
  }

  void _showPlaylistOverlay(FolderSummary folder, [List<Track>? tracks]) {
    _overlay = LibraryPlaybackOverlay.playlist(
      folder: folder,
      tracks: tracks ?? _tracksByFolder[folder.path] ?? const <Track>[],
    );
  }

  void _showFavoritesOverlay() {
    _overlay = const LibraryPlaybackOverlay.favorites();
  }

  void _saveBrowseScrollForFavoritesOverlay() {
    if (_view == LibraryView.albums && _overlay?.isAlbum != true) {
      _saveAlbumGridScrollOffset();
    }
    if (_view == LibraryView.playlists && _activePlaylistOverlayPath == null) {
      _savePlaylistListScrollOffset();
    }
    if (_view == LibraryView.favorites && _overlay?.isFavorites != true) {
      _saveFavoritesListScrollOffset();
    }
  }

  void _bindAlbumPlayback(AlbumSummary album, List<Track> tracks) {
    final current = _activeAlbumPlayback;
    if (current != null &&
        current.album.folderPath == album.folderPath &&
        _playback.isCurrentQueue(current.tracks)) {
      return;
    }
    _activeAlbumPlayback = LibraryActiveAlbumPlayback(
      album: album,
      tracks: tracks,
    );
  }

  void _bindFavoritesPlayback(LibraryNowPlayingTarget target) {
    if (target.kind != LibraryNowPlayingKind.favorites ||
        target.tracks.isEmpty ||
        target.queue.isEmpty) {
      return;
    }
    final current = _activeFavoritesPlayback;
    if (current != null && _playback.isCurrentQueue(current.queue)) {
      return;
    }
    _activeFavoritesPlayback = LibraryActiveFavoritesPlayback(
      tracks: target.tracks,
      queue: target.queue,
      shuffled: target.shuffled,
    );
  }

  void _syncActiveSelectionsWithLibrary() {
    final folders = _library.folders;
    final albums = _library.albums;
    final tracks = _library.tracks;
    final activePlaylistOverlayPath = _activePlaylistOverlayPath;
    if (activePlaylistOverlayPath != null &&
        playlistFolderForPath(activePlaylistOverlayPath, folders) == null) {
      _overlay = null;
    }

    final currentTrackPaths = tracks.map((track) => track.path).toSet();
    final overlayAlbum = _overlay?.album;
    if (_overlay?.isAlbum == true &&
        overlayAlbum != null &&
        !albums.any((album) => album.folderPath == overlayAlbum.folderPath)) {
      _overlay = null;
    }

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

    final activeFavorites = _activeFavoritesPlayback;
    if (activeFavorites != null) {
      final availableFavoritePaths = _library.favoriteTrackPaths
          .where(currentTrackPaths.contains)
          .toSet();
      if (!activeFavorites.queue.any(
        (track) => availableFavoritePaths.contains(track.path),
      )) {
        _activeFavoritesPlayback = null;
        _lastPlaybackPath = null;
        _lastPlaybackPlaying = false;
      }
    }
  }

  void _handlePlaybackChanged() {
    final activeAlbumPlayback = _activeAlbumPlayback;
    final activePlaylistPlayback = _activePlaylistPlayback;
    final activeFavoritesPlayback = _activeFavoritesPlayback;
    if (!mounted) {
      return;
    }
    _showPlaybackErrorIfNeeded();
    _saveCurrentPlaybackStateIfChanged();
    final displayTrack = activeAlbumPlayback == null
        ? activePlaylistPlayback == null
              ? activeFavoritesPlayback == null
                    ? _playback.currentTrack
                    : _currentTrackForFavorites(activeFavoritesPlayback)
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

  void _showBackgroundWarningIfNeeded() {
    final warning = _library.backgroundWarning;
    if (warning == null) {
      _lastShownBackgroundWarning = null;
      return;
    }
    if (warning == _lastShownBackgroundWarning) {
      return;
    }
    _lastShownBackgroundWarning = warning;
    _showTransientMessage(warning, onDismiss: _library.clearBackgroundWarning);
  }

  void _showTransientMessage(String message, {VoidCallback? onDismiss}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: onDismiss ?? () {},
            ),
          ),
        );
    });
  }

  void _showPlaybackErrorIfNeeded() {
    final error = _playback.playbackError;
    final errorRevision = _playback.playbackErrorRevision;
    if (error == null) {
      _lastShownPlaybackErrorRevision = null;
      return;
    }
    if (errorRevision == _lastShownPlaybackErrorRevision) {
      return;
    }
    _lastShownPlaybackErrorRevision = errorRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _playback.playbackError != error ||
          _playback.playbackErrorRevision != errorRevision) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: _playback.clearPlaybackError,
            ),
          ),
        );
    });
  }

  void _returnToNowPlayingIfNeeded() {
    if (!mounted ||
        _rescanDialogOpen ||
        _settingsDialogOpen ||
        !_playback.playing ||
        _playback.currentTrack == null) {
      return;
    }
    final target = _nowPlayingTarget;
    if (target == null || _isShowingNowPlayingTarget(target)) {
      return;
    }
    _openNowPlaying(target);
  }

  bool _isShowingNowPlayingTarget(LibraryNowPlayingTarget target) {
    return switch (target.kind) {
      LibraryNowPlayingKind.album =>
        _overlay?.isAlbum == true &&
            _overlay?.album?.folderPath == target.album?.folderPath,
      LibraryNowPlayingKind.playlist =>
        _overlay?.isPlaylist == true &&
            _overlay?.folder?.path == target.folder?.path,
      LibraryNowPlayingKind.favorites =>
        _overlay?.isFavorites == true &&
            _activeFavoritesPlayback != null &&
            _playback.isCurrentQueue(target.queue),
    };
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
        case LastPlaybackKind.favorites:
          await _restoreFavoritesPlayback(state);
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
      _showAlbumOverlay(album, tracks);
      _activeAlbumPlayback = LibraryActiveAlbumPlayback(
        album: album,
        tracks: tracks,
      );
      _activePlaylistPlayback = null;
      _activeFavoritesPlayback = null;
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
      _showPlaylistOverlay(folder, tracks);
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = LibraryActivePlaylistPlayback(
        folderPath: folder.path,
        tracks: tracks,
        queue: queue,
        shuffled: state.shuffled,
      );
      _activeFavoritesPlayback = null;
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _restoreQueueFrom(queue, track, play: state.playing);
  }

  Future<void> _restoreFavoritesPlayback(LastPlaybackState state) async {
    final tracks = _library.favoriteTracks;
    if (tracks.isEmpty || !mounted) {
      return;
    }
    final queue = state.shuffled ? shuffledTracks(tracks) : tracks;
    final track = trackByPathOrFirst(queue, state.trackPath);
    _mutate(() {
      _showFavoritesOverlay();
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = null;
      _activeFavoritesPlayback = LibraryActiveFavoritesPlayback(
        tracks: tracks,
        queue: queue,
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
      activeFavorites: _activeFavoritesPlayback,
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
        _overlay = null;
        _activeAlbumPlayback = null;
        _activePlaylistPlayback = null;
        _activeFavoritesPlayback = null;
      });
    }
  }

  Future<void> _playQueueFrom(List<Track> queue, Track track) {
    return _playback.playQueueFrom(queue, track);
  }

  void _toggleFavoriteTrack(Track track) {
    _favoriteMutation = _favoriteMutation
        .then((_) => _toggleFavoriteTrackAndSyncQueue(track))
        .catchError((_) {});
    unawaited(_favoriteMutation);
  }

  Future<void> _toggleFavoriteTrackAndSyncQueue(Track track) async {
    final removing = _library.favoriteTrackPaths.contains(track.path);
    final session = _activeFavoritesPlayback;
    final favoritesSessionActive =
        session != null && _playback.isCurrentQueue(session.queue);

    await _library.toggleFavoriteTrack(track);
    if (!mounted || !removing || !favoritesSessionActive) {
      return;
    }

    final nextTracks = session.tracks
        .where((candidate) => candidate.path != track.path)
        .toList(growable: false);
    final nextQueue = session.queue
        .where((candidate) => candidate.path != track.path)
        .toList(growable: false);
    _mutate(() {
      _activeFavoritesPlayback = nextQueue.isEmpty
          ? null
          : LibraryActiveFavoritesPlayback(
              tracks: nextTracks,
              queue: nextQueue,
              shuffled: session.shuffled,
            );
    });
    if (nextQueue.isEmpty || _playback.currentTrack?.path == track.path) {
      await _playback.stopIfCurrentRemoved([track.path]);
      return;
    }
    await _playback.replaceQueueKeepingPosition(nextQueue);
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
      _showAlbumOverlay(album, tracks);
      _activeAlbumPlayback = LibraryActiveAlbumPlayback(
        album: album,
        tracks: tracks,
      );
      _activePlaylistPlayback = null;
      _activeFavoritesPlayback = null;
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
      _showAlbumOverlay(album, tracks);
      final identity = _activeAlbumPlayback;
      final showingCurrentAlbum =
          identity != null &&
          identity.album.folderPath == album.folderPath &&
          _playback.isCurrentQueue(identity.tracks);
      final currentAlbumTrack = showingCurrentAlbum
          ? _currentTrackForAlbum(identity)
          : null;
      _lastPlaybackPath = currentAlbumTrack?.path;
      _lastPlaybackPlaying = currentAlbumTrack != null && _playback.playing;
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
    final viewed = _viewedAlbumPlayback;
    if (viewed == null) {
      return;
    }
    final target = _albumPlaybackSwitchTarget(viewed.album, delta);
    if (target == null) {
      return;
    }
    _mutate(() {
      _showAlbumOverlay(target.album, target.tracks);
      final identity = _activeAlbumPlayback;
      final showingCurrentAlbum =
          identity != null &&
          identity.album.folderPath == target.album.folderPath &&
          _playback.isCurrentQueue(identity.tracks);
      final currentAlbumTrack = showingCurrentAlbum
          ? _currentTrackForAlbum(identity)
          : null;
      _lastPlaybackPath = currentAlbumTrack?.path;
      _lastPlaybackPlaying = currentAlbumTrack != null && _playback.playing;
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
      _showPlaylistOverlay(folder, tracks);
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = LibraryActivePlaylistPlayback(
        folderPath: folder.path,
        tracks: tracks,
        queue: tracks,
        shuffled: false,
      );
      _activeFavoritesPlayback = null;
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
      _showPlaylistOverlay(folder, tracks);
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = LibraryActivePlaylistPlayback(
        folderPath: folder.path,
        tracks: tracks,
        queue: shuffled,
        shuffled: true,
      );
      _activeFavoritesPlayback = null;
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _playQueueFrom(shuffled, shuffled.first);
  }

  Future<void> _playFavorites(List<Track> tracks, {Track? startTrack}) async {
    if (tracks.isEmpty) {
      return;
    }
    final queue = tracks.toList(growable: false);
    _mutate(() {
      _showFavoritesOverlay();
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = null;
      _activeFavoritesPlayback = LibraryActiveFavoritesPlayback(
        tracks: tracks,
        queue: queue,
        shuffled: false,
      );
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _playQueueFrom(queue, startTrack ?? queue.first);
  }

  Future<void> _playFavoritesShuffled(List<Track> tracks) async {
    if (tracks.isEmpty) {
      return;
    }
    final queue = shuffledTracks(tracks);
    _mutate(() {
      _showFavoritesOverlay();
      _activeAlbumPlayback = null;
      _activePlaylistPlayback = null;
      _activeFavoritesPlayback = LibraryActiveFavoritesPlayback(
        tracks: tracks,
        queue: queue,
        shuffled: true,
      );
      _lastPlaybackPath = null;
      _lastPlaybackPlaying = false;
    });
    await _playQueueFrom(queue, queue.first);
  }

  Future<void> _playFavoriteTrack(Track track) {
    return _playFavorites(_library.favoriteTracks, startTrack: track);
  }

  void _openFavoritesPlaybackFromTrack(Track track) {
    _saveBrowseScrollForFavoritesOverlay();
    final nowPlaying = _nowPlayingTarget;
    final alreadyThisTrack =
        _playback.currentTrack?.path == track.path &&
        (nowPlaying?.kind == LibraryNowPlayingKind.favorites ||
            (_activeFavoritesPlayback != null &&
                _playback.isCurrentQueue(_activeFavoritesPlayback!.queue)));
    if (alreadyThisTrack) {
      _mutate(() {
        _showFavoritesOverlay();
        if (nowPlaying != null) {
          _bindFavoritesPlayback(nowPlaying);
        }
      });
      return;
    }
    unawaited(_playFavoriteTrack(track));
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
      activeFavorites: _activeFavoritesPlayback,
      albums: _library.albums,
      folders: _library.folders,
      favoriteTracks: _library.favoriteTracks,
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
          _showAlbumOverlay(album, tracks);
          _bindAlbumPlayback(album, tracks);
          _lastPlaybackPath = _playback.currentTrack?.path;
          _lastPlaybackPlaying = _playback.playing;
        });
      case LibraryNowPlayingKind.playlist:
        final folder = target.folder;
        if (folder == null) {
          return;
        }
        _openPlaylistPlayback(folder);
      case LibraryNowPlayingKind.favorites:
        _saveBrowseScrollForFavoritesOverlay();
        _mutate(() {
          _showFavoritesOverlay();
          _bindFavoritesPlayback(target);
        });
    }
  }

  void _openPlaylistPlayback(FolderSummary folder) {
    if (_view == LibraryView.playlists) {
      _savePlaylistListScrollOffset();
    }
    _mutate(() {
      _showPlaylistOverlay(folder);
    });
  }

  void _selectLibraryView(LibraryView view) {
    final currentView = _sidebarSelected;
    if (currentView == view && _overlay == null) {
      return;
    }

    if (_view == LibraryView.albums && view != LibraryView.albums) {
      _saveAlbumGridScrollOffset();
    }
    if (_view == LibraryView.playlists &&
        view != LibraryView.playlists &&
        _activePlaylistOverlayPath == null) {
      _savePlaylistListScrollOffset();
    }
    if (_view == LibraryView.favorites &&
        view != LibraryView.favorites &&
        !_favoritesOverlayOpen) {
      _saveFavoritesListScrollOffset();
    }
    _mutate(() {
      _view = view;
      _overlay = null;
    });
    if (view == LibraryView.albums) {
      _restoreAlbumGridScrollOffset();
    }
    if (view == LibraryView.playlists) {
      _restorePlaylistListScrollOffset();
    }
    if (view == LibraryView.favorites) {
      _restoreFavoritesListScrollOffset();
    }
  }

  void _openSettingsModal() {
    if (!_library.settingsLoaded) {
      return;
    }
    if (_settingsDialogOpen) {
      return;
    }
    _settingsDialogOpen = true;
    unawaited(
      showLibrarySettingsDialog(
        context: context,
        library: _library,
        playback: _playback,
      ).whenComplete(() => _settingsDialogOpen = false),
    );
  }

  void _closeAlbumPlayback() {
    _mutate(() => _overlay = null);
    _restoreAlbumGridScrollOffset();
  }

  void _closePlaylistPlayback() {
    _mutate(() => _overlay = null);
    _restorePlaylistListScrollOffset();
  }

  void _closeFavoritesOverlay() {
    _mutate(() => _overlay = null);
    if (_view == LibraryView.playlists) {
      _restorePlaylistListScrollOffset();
    } else if (_view == LibraryView.favorites) {
      _restoreFavoritesListScrollOffset();
    } else {
      _restoreAlbumGridScrollOffset();
    }
  }

  LibraryNowPlayingTarget? _dockNowPlayingTarget({
    required LibraryNowPlayingTarget? nowPlayingTarget,
    required AlbumSummary? viewedAlbum,
  }) {
    if (viewedAlbum == null || nowPlayingTarget == null) {
      return null;
    }
    if (nowPlayingTarget.kind == LibraryNowPlayingKind.album &&
        nowPlayingTarget.album?.folderPath == viewedAlbum.folderPath) {
      return null;
    }
    return nowPlayingTarget;
  }

  LibraryPlaylistPlaybackSwitchTarget? _playlistPlaybackSwitchTarget(
    FolderSummary folder,
    int delta,
  ) {
    return playlistPlaybackSwitchTarget(
      folder: folder,
      delta: delta,
      folders: _playlistFolders,
      tracksByFolder: _tracksByFolder,
    );
  }

  void _switchPlaylistPlayback(int delta) {
    final folder = _activePlaylistOverlayFolder;
    if (folder == null) {
      return;
    }
    final target = _playlistPlaybackSwitchTarget(folder, delta);
    if (target == null) {
      return;
    }
    _mutate(() {
      _showPlaylistOverlay(target.folder, target.tracks);
    });
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

  Track? _currentTrackForFavorites(
    LibraryActiveFavoritesPlayback favoritesPlayback,
  ) {
    return currentTrackForFavorites(
      favoritesPlayback: favoritesPlayback,
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

  void _saveFavoritesListScrollOffset() {
    _scrollMemory.saveFavoritesListScrollOffset();
  }

  void _restoreFavoritesListScrollOffset() {
    _scrollMemory.restoreFavoritesListScrollOffset(
      isMounted: () => mounted,
      currentView: () => _view,
      hasFavoritesOverlay: () => _favoritesOverlayOpen,
    );
  }

  void _restorePlaylistListScrollOffset() {
    _scrollMemory.restorePlaylistListScrollOffset(
      isMounted: () => mounted,
      currentView: () => _view,
      hasPlaylistOverlay: () => _activePlaylistOverlayPath != null,
    );
  }
}
