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

  void _syncActiveSelectionsWithLibrary() {
    final playlistPath = _activePlaylistOverlayPath;
    final album = _overlay?.album;
    if ((playlistPath != null &&
            playlistFolderForPath(playlistPath, _library.folders) == null) ||
        (album != null &&
            !_library.albums.any(
              (candidate) => candidate.folderPath == album.folderPath,
            ))) {
      _overlay = null;
    }
  }

  void _handlePlaybackChanged() {
    if (!mounted) return;
    _showPlaybackErrorIfNeeded();
    final session = _playback.session;
    if (identical(session, _lastRenderedSession) &&
        _playback.playing == _lastRenderedPlaying) {
      return;
    }
    _mutate(() {
      _lastRenderedSession = session;
      _lastRenderedPlaying = _playback.playing;
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

  void _showTransientMessage(
    String message, {
    VoidCallback? onDismiss,
    VoidCallback? onRetry,
  }) {
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
              label: onRetry == null ? 'Dismiss' : 'Retry',
              onPressed: onRetry ?? onDismiss ?? () {},
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
      LastPlaybackKind.album =>
        _overlay?.isAlbum == true &&
            _overlay?.album?.folderPath == target.album?.folderPath,
      LastPlaybackKind.playlist =>
        _overlay?.isPlaylist == true &&
            _overlay?.folder?.path == target.folder?.path,
      LastPlaybackKind.favorites =>
        _overlay?.isFavorites == true &&
            _activeFavoritesPlayback != null &&
            _playback.isCurrentQueue(target.queue),
    };
  }

  Future<void> _restoreLastPlaybackIfReady() async {
    final restored = await _libraryPlayback.restoreIfReady();
    if (!mounted || restored == null) return;
    final target = _nowPlayingTarget;
    if (target != null) _openNowPlaying(target);
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
    final changed = await _library.changeMusicRoot(nextRoot);
    if (mounted && changed) _mutate(() => _overlay = null);
  }

  void _toggleFavoriteTrack(Track track) {
    unawaited(
      _libraryPlayback.toggleFavorite(track).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        reportAppError('toggle favorite', error, stackTrace);
        if (mounted) _showTransientMessage('Could not update favorite: $error');
      }),
    );
  }

  Future<void> _playAlbumFrom(
    AlbumSummary album,
    List<Track> tracks,
    Track track,
  ) async {
    if (tracks.isEmpty) return;
    _saveAlbumGridScrollOffset();
    _mutate(() => _showAlbumOverlay(album, tracks));
    await _libraryPlayback.play(
      kind: LastPlaybackKind.album,
      folderPath: album.folderPath,
      tracks: tracks,
      startTrack: track,
    );
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
    _mutate(() => _showAlbumOverlay(album, tracks));
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
    _mutate(() => _showAlbumOverlay(target.album, target.tracks));
  }

  Future<void> _playPlaylist(
    FolderSummary folder,
    List<Track> tracks, {
    Track? startTrack,
    bool shuffled = false,
  }) async {
    if (tracks.isEmpty) return;
    _mutate(() => _showPlaylistOverlay(folder, tracks));
    await _libraryPlayback.play(
      kind: LastPlaybackKind.playlist,
      folderPath: folder.path,
      tracks: tracks,
      startTrack: startTrack,
      shuffled: shuffled,
    );
  }

  Future<void> _playPlaylistShuffled(
    FolderSummary folder,
    List<Track> tracks,
  ) => _playPlaylist(folder, tracks, shuffled: true);

  Future<void> _playFavorites(
    List<Track> tracks, {
    Track? startTrack,
    bool shuffled = false,
  }) async {
    if (tracks.isEmpty) return;
    _mutate(_showFavoritesOverlay);
    await _libraryPlayback.play(
      kind: LastPlaybackKind.favorites,
      tracks: tracks,
      startTrack: startTrack,
      shuffled: shuffled,
    );
  }

  Future<void> _playFavoritesShuffled(List<Track> tracks) =>
      _playFavorites(tracks, shuffled: true);

  Future<void> _playFavoriteTrack(Track track) {
    return _playFavorites(_library.favoriteTracks, startTrack: track);
  }

  void _openFavoritesPlaybackFromTrack(Track track) {
    _saveBrowseScrollForFavoritesOverlay();
    final nowPlaying = _nowPlayingTarget;
    final alreadyThisTrack =
        _playback.currentTrack?.path == track.path &&
        (nowPlaying?.kind == LastPlaybackKind.favorites ||
            (_activeFavoritesPlayback != null &&
                _playback.isCurrentQueue(_activeFavoritesPlayback!.queue)));
    if (alreadyThisTrack) {
      _mutate(() {
        _showFavoritesOverlay();
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
      session: _playback.session,
      playing: _playback.playing,
      albums: _library.albums,
      folders: _library.folders,
      trackCoverCache: _library.trackCoverCache,
    );
  }

  void _openNowPlaying(LibraryNowPlayingTarget target) {
    switch (target.kind) {
      case LastPlaybackKind.album:
        final album = target.album;
        final tracks = target.tracks;
        if (album == null || tracks.isEmpty) {
          return;
        }
        _saveAlbumGridScrollOffset();
        _mutate(() {
          _showAlbumOverlay(album, tracks);
        });
      case LastPlaybackKind.playlist:
        final folder = target.folder;
        if (folder == null) {
          return;
        }
        _openPlaylistPlayback(folder);
      case LastPlaybackKind.favorites:
        _saveBrowseScrollForFavoritesOverlay();
        _mutate(() {
          _showFavoritesOverlay();
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
    if (nowPlayingTarget.kind == LastPlaybackKind.album &&
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
