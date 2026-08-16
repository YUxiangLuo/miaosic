import 'dart:async';

import 'package:flutter/material.dart';

import 'library_controller.dart';
import 'library_screen_dialogs.dart';
import 'library_screen_models.dart';
import 'library_screen_selectors.dart';
import 'library_screen_view.dart';
import 'library_types.dart';
import 'models.dart';
import 'playback_controller.dart';

part 'library_screen_actions.dart';

typedef LibraryScreenClock = DateTime Function();

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.libraryController,
    this.playbackController,
    this.now = DateTime.now,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final LibraryController? libraryController;
  final PlaybackController? playbackController;
  final LibraryScreenClock now;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  static const _returnToNowPlayingAfter = Duration(seconds: 30);

  late final LibraryController _library;
  late final PlaybackController _playback;
  late final bool _ownsLibrary;
  late final bool _ownsPlayback;
  final _scrollMemory = LibraryScrollMemory();

  LibraryPlaybackOverlay? _overlay;
  LibraryActiveAlbumPlayback? _activeAlbumPlayback;
  LibraryActivePlaylistPlayback? _activePlaylistPlayback;
  LibraryActiveFavoritesPlayback? _activeFavoritesPlayback;
  String? _lastPlaybackPath;
  String? _lastNowPlayingPath;
  String? _lastPersistedPlaybackKey;
  bool _lastPlaybackPlaying = false;
  bool _lastNowPlayingPlaying = false;
  bool _lastPlaybackRestoreAttempted = false;
  bool _lastPlaybackRestoring = false;
  bool _audioOutputSettingsApplied = false;
  LibraryView _view = LibraryView.albums;
  bool _rescanDialogOpen = false;
  bool _settingsDialogOpen = false;
  int? _lastShownPlaybackErrorRevision;
  String? _lastShownBackgroundWarning;
  DateTime? _appLeftAt;
  Future<void> _favoriteMutation = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _library = widget.libraryController ?? LibraryController();
    _playback = widget.playbackController ?? PlaybackController();
    _ownsLibrary = widget.libraryController == null;
    _ownsPlayback = widget.playbackController == null;
    _library.addListener(_handleLibraryChanged);
    _playback.addListener(_handlePlaybackChanged);
    unawaited(_library.open());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollMemory.dispose();
    _library.removeListener(_handleLibraryChanged);
    if (_ownsLibrary) {
      _library.dispose();
    }
    _playback.removeListener(_handlePlaybackChanged);
    if (_ownsPlayback) {
      _playback.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final leftAt = _appLeftAt;
        _appLeftAt = null;
        if (leftAt == null) {
          return;
        }
        final elapsed = widget.now().difference(leftAt);
        if (!elapsed.isNegative && elapsed >= _returnToNowPlayingAfter) {
          _returnToNowPlayingIfNeeded();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _appLeftAt ??= widget.now();
      case AppLifecycleState.detached:
        break;
    }
  }

  void _mutate(VoidCallback update) {
    setState(update);
  }

  LibraryActiveAlbumPlayback? get _viewedAlbumPlayback {
    final overlay = _overlay;
    final album = overlay?.album;
    if (overlay == null || !overlay.isAlbum || album == null) {
      return null;
    }
    final tracks = _tracksByFolder[album.folderPath] ?? overlay.tracks;
    return LibraryActiveAlbumPlayback(album: album, tracks: tracks);
  }

  FolderSummary? get _activePlaylistOverlayFolder {
    final overlay = _overlay;
    if (overlay == null || !overlay.isPlaylist) {
      return null;
    }
    return livePlaylistOverlayFolder(
      stored: overlay.folder,
      folders: _library.folders,
    );
  }

  String? get _activePlaylistOverlayPath => _activePlaylistOverlayFolder?.path;

  bool get _favoritesOverlayOpen => _overlay?.isFavorites ?? false;

  LibraryView get _sidebarSelected {
    if (_favoritesOverlayOpen) {
      return LibraryView.favorites;
    }
    return _view == LibraryView.favorites ? LibraryView.albums : _view;
  }

  @override
  Widget build(BuildContext context) {
    final viewedAlbumPlayback = _viewedAlbumPlayback;
    final albumQueue = _activeAlbumPlayback;
    final activePlaylistOverlayFolder = _activePlaylistOverlayFolder;
    final activePlaylistOverlayTracks = activePlaylistOverlayFolder == null
        ? const <Track>[]
        : _tracksByFolder[activePlaylistOverlayFolder.path] ?? const <Track>[];
    final activePlaylistPlayback = _activePlaylistPlayback;
    final activePlaylistPlaybackTrack = activePlaylistPlayback == null
        ? null
        : _currentTrackForPlaylist(activePlaylistPlayback);
    final playlistOverlayPlaybackActive =
        activePlaylistOverlayFolder != null &&
        activePlaylistPlayback != null &&
        activePlaylistPlayback.folderPath == activePlaylistOverlayFolder.path &&
        activePlaylistPlaybackTrack != null;
    final activePlaylistTrack = playlistOverlayPlaybackActive
        ? activePlaylistPlaybackTrack
        : null;
    final activeFavoritesPlayback = _activeFavoritesPlayback;
    final activeFavoritesPlaybackTrack = activeFavoritesPlayback == null
        ? null
        : _currentTrackForFavorites(activeFavoritesPlayback);
    final favoritesPlaybackActive =
        activeFavoritesPlayback != null &&
        _playback.isCurrentQueue(activeFavoritesPlayback.queue) &&
        activeFavoritesPlaybackTrack != null;
    final favoritesPlaybackQueue =
        activeFavoritesPlayback?.queue ?? const <Track>[];
    final favoritesPlaybackIndex = activeFavoritesPlaybackTrack == null
        ? -1
        : favoritesPlaybackQueue.indexWhere(
            (track) => track.path == activeFavoritesPlaybackTrack.path,
          );
    final settingsLoaded = _library.settingsLoaded;
    final viewingNowPlayingAlbum =
        viewedAlbumPlayback != null &&
        albumQueue != null &&
        viewedAlbumPlayback.album.folderPath == albumQueue.album.folderPath &&
        _playback.isCurrentQueue(albumQueue.tracks);
    final albumControlTracks = viewingNowPlayingAlbum
        ? albumQueue.tracks
        : viewedAlbumPlayback?.tracks ?? const <Track>[];
    final activeAlbumTrack = viewingNowPlayingAlbum
        ? _currentTrackForAlbum(albumQueue)
        : null;
    final nowPlayingTarget = _nowPlayingTarget;
    final dockNowPlayingTarget = _dockNowPlayingTarget(
      nowPlayingTarget: nowPlayingTarget,
      viewedAlbum: viewedAlbumPlayback?.album,
    );
    final playlistQueue = activePlaylistPlayback?.queue ?? const <Track>[];
    final playlistPlaybackIndex = activePlaylistPlaybackTrack == null
        ? -1
        : playlistQueue.indexWhere(
            (track) => track.path == activePlaylistPlaybackTrack.path,
          );

    return LibraryScreenView(
      model: LibraryScreenViewModel(
        selectedView: _sidebarSelected,
        browseView: _sidebarSelected == LibraryView.favorites
            ? (_view == LibraryView.playlists
                  ? LibraryView.playlists
                  : LibraryView.albums)
            : _sidebarSelected,
        loading: _library.loading,
        albums: _library.albums,
        playlistFolders: _playlistFolders,
        playlistCount: _playlistCount,
        favoriteTracks: _library.favoriteTracks,
        favoriteCount: _library.favoriteCount,
        favoriteTrackPaths: _library.favoriteTrackPaths,
        favoritesPlaybackActive: favoritesPlaybackActive,
        tracksByFolder: _tracksByFolder,
        trackCoverCache: _library.trackCoverCache,
        themeMode: widget.themeMode,
        nowPlayingTarget: nowPlayingTarget,
        activeAlbumPlayback: viewedAlbumPlayback,
        activeAlbumTrack: activeAlbumTrack,
        dockNowPlayingAlbumTarget: dockNowPlayingTarget,
        activePlaylistOverlayFolder: activePlaylistOverlayFolder,
        activePlaylistOverlayTracks: activePlaylistOverlayTracks,
        activePlaylistTrack: activePlaylistTrack,
        playlistOverlayPlaybackActive: playlistOverlayPlaybackActive,
        favoritesOverlayOpen: _favoritesOverlayOpen,
        playbackCurrentTrack: _playback.currentTrack,
        playbackPlaying: _playback.playing,
        albumGridScrollController: _scrollMemory.albumGridScrollController,
        playlistListScrollController:
            _scrollMemory.playlistListScrollController,
        canSwitchPreviousAlbum:
            viewedAlbumPlayback != null &&
            _albumPlaybackSwitchTarget(viewedAlbumPlayback.album, -1) != null,
        canSwitchNextAlbum:
            viewedAlbumPlayback != null &&
            _albumPlaybackSwitchTarget(viewedAlbumPlayback.album, 1) != null,
        canSwitchPreviousPlaylist:
            activePlaylistOverlayFolder != null &&
            _playlistPlaybackSwitchTarget(activePlaylistOverlayFolder, -1) !=
                null,
        canSwitchNextPlaylist:
            activePlaylistOverlayFolder != null &&
            _playlistPlaybackSwitchTarget(activePlaylistOverlayFolder, 1) !=
                null,
      ),
      actions: LibraryScreenViewActions(
        onOpenLibrary: settingsLoaded ? _openRescanModal : null,
        onToggleThemeMode: settingsLoaded ? _handleToggleThemeMode : null,
        onOpenSettings: settingsLoaded ? _openSettingsModal : null,
        onOpenNowPlaying: _openNowPlaying,
        onSelectedView: _selectLibraryView,
        onOpenAlbum: _openAlbumPlayback,
        onCloseAlbumPlayback: _closeAlbumPlayback,
        onAlbumPrevious: viewedAlbumPlayback == null
            ? null
            : () => unawaited(_playback.skip(-1, albumControlTracks)),
        onAlbumToggle: viewedAlbumPlayback == null
            ? null
            : () => unawaited(
                viewingNowPlayingAlbum
                    ? _playback.togglePlayPause(albumControlTracks)
                    : _playAlbum(
                        viewedAlbumPlayback.album,
                        viewedAlbumPlayback.tracks,
                      ),
              ),
        onAlbumNext: viewedAlbumPlayback == null
            ? null
            : () => unawaited(_playback.skip(1, albumControlTracks)),
        onOpenNowPlayingAlbum: dockNowPlayingTarget == null
            ? null
            : () => _openNowPlaying(dockNowPlayingTarget),
        onSwitchPreviousAlbum: viewedAlbumPlayback == null
            ? null
            : () => _switchAlbumPlayback(-1),
        onSwitchNextAlbum: viewedAlbumPlayback == null
            ? null
            : () => _switchAlbumPlayback(1),
        onPlayAlbumTrack: (track) {
          final viewed = _viewedAlbumPlayback;
          if (viewed == null) {
            return;
          }
          unawaited(_playAlbumFrom(viewed.album, viewed.tracks, track));
        },
        onToggleFavoriteTrack: _toggleFavoriteTrack,
        onFavoritePlayAll: _library.favoriteTracks.isEmpty
            ? null
            : () => unawaited(_playFavorites(_library.favoriteTracks)),
        onFavoriteShuffleAll: _library.favoriteTracks.isEmpty
            ? null
            : () => unawaited(_playFavoritesShuffled(_library.favoriteTracks)),
        onFavoritePrevious:
            favoritesPlaybackActive && favoritesPlaybackIndex > 0
            ? () => unawaited(_playback.skip(-1, favoritesPlaybackQueue))
            : null,
        onFavoriteTogglePlayback: favoritesPlaybackActive
            ? () => unawaited(_playback.togglePlayPause(favoritesPlaybackQueue))
            : null,
        onFavoriteNext:
            favoritesPlaybackActive &&
                favoritesPlaybackIndex >= 0 &&
                favoritesPlaybackIndex < favoritesPlaybackQueue.length - 1
            ? () => unawaited(_playback.skip(1, favoritesPlaybackQueue))
            : null,
        onOpenPlaylistPlayback: _openPlaylistPlayback,
        onCloseFavoritesPlayback: _closeFavoritesOverlay,
        onOpenNowPlayingFromFavorites:
            nowPlayingTarget == null ||
                nowPlayingTarget.kind == LibraryNowPlayingKind.favorites
            ? null
            : () => _openNowPlaying(nowPlayingTarget),
        onClosePlaylistPlayback: _closePlaylistPlayback,
        onSwitchPreviousPlaylist: activePlaylistOverlayFolder == null
            ? null
            : () => _switchPlaylistPlayback(-1),
        onSwitchNextPlaylist: activePlaylistOverlayFolder == null
            ? null
            : () => _switchPlaylistPlayback(1),
        onOpenNowPlayingFromPlaylist:
            nowPlayingTarget == null ||
                (nowPlayingTarget.kind == LibraryNowPlayingKind.playlist &&
                    nowPlayingTarget.folder?.path ==
                        activePlaylistOverlayFolder?.path)
            ? null
            : () => _openNowPlaying(nowPlayingTarget),
        onPlaylistPlayAll:
            activePlaylistOverlayFolder == null ||
                activePlaylistOverlayTracks.isEmpty
            ? null
            : () => unawaited(
                _playPlaylist(
                  activePlaylistOverlayFolder,
                  activePlaylistOverlayTracks,
                ),
              ),
        onPlaylistShuffleAll:
            activePlaylistOverlayFolder == null ||
                activePlaylistOverlayTracks.isEmpty
            ? null
            : () => unawaited(
                _playPlaylistShuffled(
                  activePlaylistOverlayFolder,
                  activePlaylistOverlayTracks,
                ),
              ),
        onPlaylistPrevious:
            playlistOverlayPlaybackActive && playlistPlaybackIndex > 0
            ? () => unawaited(_playback.skip(-1, playlistQueue))
            : null,
        onPlaylistTogglePlayback: playlistOverlayPlaybackActive
            ? () => unawaited(_playback.togglePlayPause(playlistQueue))
            : null,
        onPlaylistNext:
            playlistOverlayPlaybackActive &&
                playlistPlaybackIndex >= 0 &&
                playlistPlaybackIndex < playlistQueue.length - 1
            ? () => unawaited(_playback.skip(1, playlistQueue))
            : null,
        onPlayPlaylistTrack: (track) {
          final folder = _activePlaylistOverlayFolder;
          if (folder == null) {
            return;
          }
          final tracks = _tracksByFolder[folder.path] ?? const <Track>[];
          unawaited(_playPlaylist(folder, tracks, startTrack: track));
        },
        onPlayFavoriteTrack: (track) => unawaited(_playFavoriteTrack(track)),
      ),
    );
  }
}
